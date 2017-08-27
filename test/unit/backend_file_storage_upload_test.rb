#!/usr/bin/env ruby

require './test_helper'
require 'cgi'

# Test and examples of backend_file_storage_handler use.

# Copyright (C) 2013 Piotr Gaertig

class BackendFileStorageUploadTest < Test::Unit::TestCase

  attr_accessor :http, :req

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @req = Net::HTTP::Put.new 'http://localhost:8088/upload/backend'
    @upload_path = "/tmp"
  end

  def test_one_shot_upload
    req.body = "Part1"
    req['session-id'] = '12345'
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /id=/, res.body

    params = CGI::parse(res.body)           #echoed params in body
    assert_equal ["12345"], params['id']
    assert_equal ["/tmp/12345"], params['path']
    assert_equal ["5"], params['size']
    #assert_equal ["thefile.txt"], params['name']

    assert_equal "testvalue", res.header["X-Test"]  #check header passing
  end

  def test_one_shot_upload_no_session_id
    req.body = "Part1"
    res = http.request(req)

    assert_equal "202", res.code
    assert_match /id=/, res.body
    session_id = res.header["X-Session-Id"]
    assert_match /^[a-z0-9]{40}$/, session_id  #check generated session Id

    assert_file_content session_id, 'Part1'

    params = CGI::parse(res.body)           #echoed params in body
    assert_equal [session_id], params['id']
    assert_equal ["/tmp/#{session_id}"], params['path']
    assert_equal ["5"], params['size']
    assert_false params.has_key? 'name'  #no name

    assert_equal "testvalue", res.header["X-Test"]  #check header passing
  end

  def test_two_parts
    assert_new_file '12347', "Part1Part2" do
      req.body = "Part1"
      req['session-id'] = '12347'
      req['content-range'] = 'bytes 0-4/10'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-4/10", res.body

      assert_file_content '12347', 'Part1'

      #part2 goes
      req.body = "Part2"
      req['content-range'] = 'bytes 5-9/10'
      res = http.request(req)

      assert_equal "202", res.code
      assert_match /id=/, res.body

      params = CGI::parse(res.body)  #echoed params in body
      assert_equal ["12347"], params['id']
      assert_equal ["/tmp/12347"], params['path']
      assert_equal ["10"], params['size']
      #assert_equal ["thefile.txt"], params['name']

      assert_equal "testvalue", res.header["X-Test"]  #check header passing
    end
  end

  def test_content_disposition
    req.body = "Part1"
    req['session-id'] = '12345'
    req['Content-Disposition'] = 'attachment; filename=somename.txt'
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /name=/, res.body
    params = CGI::parse(res.body)
    assert_equal ["somename.txt"], params['name']

    req['Content-Disposition'] = 'ATTACHMENT; FILENAME=somename.txt'
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /name=/, res.body
    params = CGI::parse(res.body)
    assert_equal ["somename.txt"], params['name']

    #UTF-8
    req['Content-Disposition'] = 'attachment; filename=一部のテキスト.txt'
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /name=/, res.body
    params = CGI::parse(res.body)
    assert_equal ["一部のテキスト.txt"], params['name']

    #quotes UTF-8
    req['Content-Disposition'] = 'attachment; filename="gęślę.txt"'
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /name=/, res.body
    params = CGI::parse(res.body)
    assert_equal ["gęślę.txt"], params['name']


    #RFC conforming UTF-8 notation http://greenbytes.de/tech/webdav/rfc5987.html
    req['Content-Disposition'] = "attachment; filename*=UTF-8''źdźbło.dat"
    res = http.request(req)
    assert_equal "202", res.code
    assert_match /name=/, res.body
    params = CGI::parse(res.body)
    assert_equal ["źdźbło.dat"], params['name']
  end

  # Checksum should be passed even without crc32 handler
  def test_checksum_passing_from_client
    req.body = "SomeContent"
    req['session-id'] = '12350'
    req['X-Checksum'] = '33044b53'
    res = http.request(req)
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
end