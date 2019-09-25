#!/usr/bin/env ruby

require './test_helper'
require 'cgi'

# Test and examples of sha256 usage, serverside only
# Copyright (C) 2013 Piotr Gaertig

class Sha256HandlerTest < Test::Unit::TestCase

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @upload_path = "/tmp"
  end

  def put(body, headers)
    req = Net::HTTP::Put.new 'http://localhost:8088/upload/backend-sha256'
    headers.each {|k, v| req[k]=v }
    req.body = body
    @http.request(req)
  end

  def test_sha256_by_client
    res = put "SomeContent",
              'session-id' => 12355,
              'X-SHA256' => '0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e'

    assert_equal "202", res.code, "Problem: #{res.body}"
    assert_match /id=/, res.body

    params = CGI::parse(res.body)           #echoed params in body
    assert_equal ["12355"], params['id']
    assert_equal ["/tmp/12355"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e"], params['sha256']

    assert_equal "testvalue", res.header["X-Test"]  #check header passing
    assert_equal "0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e", res.header["X-SHA256"]
  end



  def test_bad_sha256_format
    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA256' => 'deadbeaf1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'  #too long

    assert_equal "400", res.code
    assert_equal "Bad X-SHA256 format: deadbeaf1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", res.body

    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA256' => 'xyz1'*16  #length ok but not hex

    assert_equal "400", res.code
    assert_equal "Bad X-SHA256 format: xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1", res.body
  end

  def test_sha256_mismatch
    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA256' => 'e72fd5c164c1746bd687186cbfbf24bcf64b0707297369a5494b1803bc9c5fb8'  #actually double sha256

    assert_equal "400", res.code
    assert_equal "Chunk SHA-256 mismatch client=[e72fd5c164c1746bd687186cbfbf24bcf64b0707297369a5494b1803bc9c5fb8] " +
                     "server=[0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e]", res.body
  end

  def test_sha256_server_only
    res = put "SomeContent",
              'session-id' => 12350

    assert_equal "202", res.code

    params = CGI::parse(res.body)
    assert_equal ["12350"], params['id']
    assert_equal ["/tmp/12350"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e"], params['sha256'] #calculated by server

    assert_equal "testvalue", res.header["X-Test"]
    assert_equal "0d69935e3a8ba45cf38ba6d6a8c249f5100f863344f8e704bbb00bfc352baa5e", res.header["X-SHA256"] #calculated by server
  end

  def test_sha256_server_only_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "4c4d5b2f3520c139248842229eac57d0e8b277a854c4aad91dd282870d09da09", res.header["X-SHA256"]  #sha256 of data sent so far

    res = put "Part2",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 5-9/10'  #sha256 of data sent so far

    assert_equal "202", res.code
    assert_equal "0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f", res.header["X-SHA256"]  #sha256 of data sent so far = whole data

    params = CGI::parse(res.body)
    assert_equal ["0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f"], params['sha256']
  end

  def test_sha256_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'X-SHA256' => "4c4d5b2f3520c139248842229eac57d0e8b277a854c4aad91dd282870d09da09",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "4c4d5b2f3520c139248842229eac57d0e8b277a854c4aad91dd282870d09da09", res.header["X-SHA256"]

    res = put "Part2",
              'Session-Id' => 12350,
              'X-SHA256' => "0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f", res.header["X-SHA256"]  #SHA-1 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f"], params['sha256']
  end

  #If next chunk overlaps with already uploaded SHA256 shouldn't be broken
  def test_sha256_overlapping
    res = put "Part1",
              'Session-Id' => 12359,
              'X-SHA256' => "4c4d5b2f3520c139248842229eac57d0e8b277a854c4aad91dd282870d09da09",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "4c4d5b2f3520c139248842229eac57d0e8b277a854c4aad91dd282870d09da09", res.header["X-SHA256"]  #SHA-1 of 'Part1'

    res = put "t1Part2",   # here goes some content from first request
              'Session-Id' => 12359,
              'X-SHA256' => "0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f",
              'Content-Range' => 'bytes 3-9/10'

    assert_equal "202", res.code, "#{res.code} #{res.body}"
    assert_equal "0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f", res.header["X-SHA256"]  #SHA-1 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["0348b7fa285f21fc921718d8b7e3d0508e0f3f992f6c252e2888d1a16febf46f"], params['sha256']
  end

  #More complicated overlapping scenario with one request body to ignore by sha256 engine
  def test_sha256_overlapping2
    res = put "PartOne",
              'Session-Id' => 12360,
              'X-SHA256' => "e67678748841137e5b2022d8f620d965cc4a3db9fb171e03bf4b397092ebdb10",
              'Content-Range' => 'bytes 0-6/14'

    assert_equal "201", res.code, "#{res.code} #{res.body}"
    assert_equal "e67678748841137e5b2022d8f620d965cc4a3db9fb171e03bf4b397092ebdb10", res.header["X-SHA256"]  #SHA-1 of 'PartOne'

    res = put "tOn",   # here goe fragment of data sent previously in req 1
              'Session-Id' => 12360,
              'X-SHA256' => "f1208c9b4625294690268b785d3f9c40c19101d6b1f7cdb6a21de866e417d4ff",
              'Content-Range' => 'bytes 3-5/14'

    assert_equal "201", res.code, "#{res.code} #{res.body}"
    assert_equal "f1208c9b4625294690268b785d3f9c40c19101d6b1f7cdb6a21de866e417d4ff", res.header["X-SHA256"]  #SHA-1 of 'PartOn', actually duplicated from request header

    res = put "ePartTwo",   # here goes continuation of data from req 1 and remaining data
              'Session-Id' => 12360,
              'X-SHA256' => "573a18d56a7ac3a1aefce86d0bea32a9efd57bdee7cd215a78981d8b9d2e7273",
              'Content-Range' => 'bytes 6-13/14'

    assert_equal "202", res.code, "#{res.code} #{res.body}"
    assert_equal "573a18d56a7ac3a1aefce86d0bea32a9efd57bdee7cd215a78981d8b9d2e7273", res.header["X-SHA256"]  #SHA-1 of 'PartOnePartTwo'

    params = CGI::parse(res.body)
    assert_equal ["573a18d56a7ac3a1aefce86d0bea32a9efd57bdee7cd215a78981d8b9d2e7273"], params['sha256']
  end


end