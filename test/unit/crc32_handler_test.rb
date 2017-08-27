#!/usr/bin/env ruby

require './test_helper'
require 'cgi'

# Test and examples of crc32 usage, provided by client side and server side.

# Copyright (C) 2013 Piotr Gaertig

class Crc32HandlerTest < Test::Unit::TestCase

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @upload_path = "/tmp"
  end

  def put(body, headers)
    req = Net::HTTP::Put.new 'http://localhost:8088/upload/backend-crc32'
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
    assert_equal ["9e454a7"], params['checksum']
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
              'X-Last-Checksum' =>  "3053a846",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "478ac3e5", res.header["X-Checksum"]  #CRC32 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["478ac3e5"], params['checksum']
  end

  def test_crc32_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'X-Checksum' => "3053a846",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "3053a846", res.header["X-Checksum"]

    res = put "Part2",
              'Session-Id' => 12350,
              'X-Last-Checksum' =>  "3053a846",
              'X-Checksum' => "478ac3e5",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "478ac3e5", res.header["X-Checksum"]  #CRC32 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["478ac3e5"], params['checksum']

  end

  #The next part request doesn't carry X-Last-Checksum so server-side checksum calculation shouldn't be continued
  def test_crc32_two_parts_without_continuation
    res = put "Part1",
              'Session-Id' => 12350,
              'X-Checksum' => "3053a846",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "3053a846", res.header["X-Checksum"]

    res = put "Part2",
              'Session-Id' => 12350,
              'X-Checksum' => "478ac3e5",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "478ac3e5", res.header["X-Checksum"]  #CRC32 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["478ac3e5"], params['checksum']
  end


end