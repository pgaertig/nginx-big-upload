#!/usr/bin/env ruby

require './test_helper'
require 'cgi'
require 'zlib'

# Test and examples of crc32 server side state usage, provided by client side and server side.

class Crc32ServerHandlerTest < Test::Unit::TestCase

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @upload_path = "/tmp"
  end

  def put(body, headers)
    req = Net::HTTP::Put.new 'http://localhost:8088/upload/backend-crc32s'
    headers.each {|k, v| req[k]=v }
    req.body = body
    @http.request(req)
  end

  def test_crc32_by_client
    res = put "SomeContent",
              'session-id' => 12350,
              'X-Checksum' => '33044b53'

    assert_equal "202", res.code
    assert_match /id=/, res.body

    params = CGI::parse(res.body)           #echoed params in body
    assert_equal ["12350"], params['id']
    assert_equal ["/tmp/12350"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["33044b53"], params['checksum']
    #assert_equal ["thefile.txt"], params['name']

    assert_equal "testvalue", res.header["X-Test"]  #check header passing
    assert_equal "33044b53", res.header["X-Checksum"]
  end

  def test_bad_crc32_format
    res = put "SomeContent",
              'session-id' => 12350,
              'X-Checksum' => 'deadbeaf1'  #too long

    assert_equal "400", res.code
    assert_equal "Bad X-Checksum format: deadbeaf1", res.body

    res = put "SomeContent",
              'session-id' => 12350,
              'X-Checksum' => 'xyzxyz12'  #not hex

    assert_equal "400", res.code
    assert_equal "Bad X-Checksum format: xyzxyz12", res.body
  end

  def test_crc32_with_no_leading_zeros
    res = put "crc32_with_zeros7389",
              'session-id' => 12350,
              'X-Checksum' => '9e454a7'  #shorter

    assert_equal "202", res.code
    params = CGI::parse(res.body)
    assert_equal ["09e454a7"], params['checksum']
  end


  def test_crc32_mismatch
    res = put "SomeContent",
              'session-id' => 12350,
              'X-Checksum' => 'deadbeef'  #too long

    assert_equal "400", res.code
    assert_equal "Chunk checksum mismatch client=[deadbeef] server=[33044b53]", res.body
  end

  def test_crc32_server_only
    res = put "SomeContent",
              'session-id' => 12350

    assert_equal "202", res.code

    params = CGI::parse(res.body)
    assert_equal ["12350"], params['id']
    assert_equal ["/tmp/12350"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["33044b53"], params['checksum'] #calculated by server

    assert_equal "testvalue", res.header["X-Test"]
    assert_equal "33044b53", res.header["X-Checksum"] #calculated by server
  end

  def test_crc32_server_only_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "3053a846", res.header["X-Checksum"]

    res = put "Part2",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "478ac3e5", res.header["X-Checksum"]  #CRC32 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["478ac3e5"], params['checksum']
  end

  def test_crc32_two_parts_with_validation
    res = put "Part1",
              'Session-Id' => 12350,
              'X-Checksum' => "3053a846",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "3053a846", res.header["X-Checksum"]

    res = put "Part2",
              'Session-Id' => 12350,
              'X-Checksum' => "66666666",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "400", res.code
    assert_equal "Chunk checksum mismatch client=[66666666] server=[478ac3e5]", res.body
  end


  DATA = 'Part1Part2Part3Part4Part5Part6Part7Part8'  #40 bytes, five per "PartN"

  def crc(upto)
    '%08x' % Zlib.crc32(DATA[0, upto])
  end

  #The client lost the response to a large chunk and came back with a smaller one, which happens
  #whenever a timeout drops the adaptive chunk size. Server-side state is authoritative in this
  #mode, so bytes it has already counted must be skipped instead of folded in a second time.
  def test_crc32_overlapping_after_chunk_size_drop
    sid = '12371'

    res = put DATA[0, 20], 'Session-Id' => sid, 'Content-Range' => 'bytes 0-19/40'
    assert_equal "201", res.code
    assert_equal crc(20), res.header["X-Checksum"]

    #Retry lying entirely inside what the server holds: nothing to add, so nothing is reported
    res = put DATA[10, 5], 'Session-Id' => sid, 'Content-Range' => 'bytes 10-14/40'
    assert_equal "201", res.code
    assert_nil res.header["X-Checksum"]

    #Retry ending exactly on the boundary: state is rewritten, the value does not move
    res = put DATA[15, 5], 'Session-Id' => sid, 'Content-Range' => 'bytes 15-19/40'
    assert_equal "201", res.code
    assert_equal crc(20), res.header["X-Checksum"]

    #The chunk size ramps up again and straddles the boundary: only bytes 20-29 are counted
    res = put DATA[15, 15], 'Session-Id' => sid, 'Content-Range' => 'bytes 15-29/40'
    assert_equal "201", res.code
    assert_equal crc(30), res.header["X-Checksum"]

    res = put DATA[30, 10], 'Session-Id' => sid, 'Content-Range' => 'bytes 30-39/40'
    assert_equal "202", res.code
    assert_equal [crc(40)], CGI::parse(res.body)['checksum']

    assert_file_content sid, DATA
  end

  #The response to the last chunk was lost, so the client sends that chunk again. The whole of it is
  #then an overlap and the checksum must come out unchanged rather than doubled.
  def test_crc32_repeated_last_chunk
    sid = '12372'

    res = put DATA[0, 30], 'Session-Id' => sid, 'Content-Range' => 'bytes 0-29/40'
    assert_equal "201", res.code
    assert_equal crc(30), res.header["X-Checksum"]

    res = put DATA[30, 10], 'Session-Id' => sid, 'Content-Range' => 'bytes 30-39/40'
    assert_equal "202", res.code
    assert_equal [crc(40)], CGI::parse(res.body)['checksum']

    res = put DATA[30, 10], 'Session-Id' => sid, 'Content-Range' => 'bytes 30-39/40'
    assert_equal "202", res.code
    assert_equal [crc(40)], CGI::parse(res.body)['checksum']

    assert_file_content sid, DATA
  end

end