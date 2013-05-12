#!/usr/bin/env ruby

require './test_helper'
require 'cgi'

# Test and examples of sha1 usage, serverside only
# Copyright (C) 2013 Piotr Gaertig

class Sha1HandlerTest < Test::Unit::TestCase

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @upload_path = "/tmp"
  end

  def put(body, headers)
    req = Net::HTTP::Put.new 'http://localhost:8088/upload/backend-sha1'
    headers.each {|k, v| req[k]=v }
    req.body = body
    @http.request(req)
  end

  def test_sha1_by_client
    res = put "SomeContent",
              'session-id' => 12355,
              'X-SHA1' => '91167568d95aa6a95fbca99a1eb3dccffe27103a'

    assert_equal "202", res.code
    assert_match /id=/, res.body

    params = CGI::parse(res.body)           #echoed params in body
    assert_equal ["12355"], params['id']
    assert_equal ["/tmp/12355"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["91167568d95aa6a95fbca99a1eb3dccffe27103a"], params['sha1']

    assert_equal "testvalue", res.header["X-Test"]  #check header passing
    assert_equal "91167568d95aa6a95fbca99a1eb3dccffe27103a", res.header["X-SHA1"]
  end



  def test_bad_sha1_format
    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA1' => 'deadbeaf1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'  #too long

    assert_equal "400", res.code
    assert_equal "Bad X-SHA1 format: deadbeaf1aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", res.body

    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA1' => 'xyz1'*10  #length ok but not hex

    assert_equal "400", res.code
    assert_equal "Bad X-SHA1 format: xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1xyz1", res.body
  end

  def test_sha1_mismatch
    res = put "SomeContent",
              'session-id' => 12350,
              'X-SHA1' => 'd51e72139f7fc1fbf27efeca45d8061efda25420'  #actually double sha1

    assert_equal "400", res.code
    assert_equal "Chunk SHA-1 mismatch client=[d51e72139f7fc1fbf27efeca45d8061efda25420] server=[91167568d95aa6a95fbca99a1eb3dccffe27103a]", res.body
  end

  def test_sha1_server_only
    res = put "SomeContent",
              'session-id' => 12350

    assert_equal "202", res.code

    params = CGI::parse(res.body)
    assert_equal ["12350"], params['id']
    assert_equal ["/tmp/12350"], params['path']
    assert_equal ["11"], params['size']
    assert_equal ["91167568d95aa6a95fbca99a1eb3dccffe27103a"], params['sha1'] #calculated by server

    assert_equal "testvalue", res.header["X-Test"]
    assert_equal "91167568d95aa6a95fbca99a1eb3dccffe27103a", res.header["X-SHA1"] #calculated by server
  end

  def test_sha1_server_only_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "138d033e6d97d507ae613bd0c29b7ed365f19395", res.header["X-SHA1"]  #sha1 of data sent so far

    res = put "Part2",
              'Session-Id' => 12350,
              'Content-Range' => 'bytes 5-9/10'  #sha1 of data sent so far

    assert_equal "202", res.code
    assert_equal "988dced4ecae71ee10dd5d8ddb97adb62c537704", res.header["X-SHA1"]  #sha1 of data sent so far = whole data

    params = CGI::parse(res.body)
    assert_equal ["988dced4ecae71ee10dd5d8ddb97adb62c537704"], params['sha1']
  end

  def test_sha1_two_parts
    res = put "Part1",
              'Session-Id' => 12350,
              'X-SHA1' => "138d033e6d97d507ae613bd0c29b7ed365f19395",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "138d033e6d97d507ae613bd0c29b7ed365f19395", res.header["X-SHA1"]

    res = put "Part2",
              'Session-Id' => 12350,
              'X-SHA1' => "988dced4ecae71ee10dd5d8ddb97adb62c537704",
              'Content-Range' => 'bytes 5-9/10'

    assert_equal "202", res.code
    assert_equal "988dced4ecae71ee10dd5d8ddb97adb62c537704", res.header["X-SHA1"]  #SHA-1 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["988dced4ecae71ee10dd5d8ddb97adb62c537704"], params['sha1']
  end

  #If next chunk overlaps with already uploaded SHA1 shouldn't be broken
  def test_sha1_overlapping
    res = put "Part1",
              'Session-Id' => 12359,
              'X-SHA1' => "138d033e6d97d507ae613bd0c29b7ed365f19395",
              'Content-Range' => 'bytes 0-4/10'

    assert_equal "201", res.code
    assert_equal "138d033e6d97d507ae613bd0c29b7ed365f19395", res.header["X-SHA1"]  #SHA-1 of 'Part1'

    res = put "t1Part2",   # here goes some content from first request
              'Session-Id' => 12359,
              'X-SHA1' => "988dced4ecae71ee10dd5d8ddb97adb62c537704",
              'Content-Range' => 'bytes 3-9/10'

    assert_equal "202", res.code, "#{res.code} #{res.body}"
    assert_equal "988dced4ecae71ee10dd5d8ddb97adb62c537704", res.header["X-SHA1"]  #SHA-1 of 'Part1Part2'

    params = CGI::parse(res.body)
    assert_equal ["988dced4ecae71ee10dd5d8ddb97adb62c537704"], params['sha1']
  end

  #More complicated overlapping scenario with one request body to ignore by sha1 engine
  def test_sha1_overlapping2
    res = put "PartOne",
              'Session-Id' => 12360,
              'X-SHA1' => "dbea4eb50b509799a715084d0eb3d2c68972a068",
              'Content-Range' => 'bytes 0-6/14'

    assert_equal "201", res.code
    assert_equal "dbea4eb50b509799a715084d0eb3d2c68972a068", res.header["X-SHA1"]  #SHA-1 of 'PartOne'

    res = put "tOn",   # here goe fragment of data sent previously in req 1
              'Session-Id' => 12360,
              'X-SHA1' => "f09ecfe7b56886772924c2e56c845f38cb037014",
              'Content-Range' => 'bytes 3-5/14'

    assert_equal "201", res.code, "#{res.code} #{res.body}"
    assert_equal "f09ecfe7b56886772924c2e56c845f38cb037014", res.header["X-SHA1"]  #SHA-1 of 'PartOn', actually duplicated from request header

    res = put "ePartTwo",   # here goes continuation of data from req 1 and remaining data
              'Session-Id' => 12360,
              'X-SHA1' => "914e861a274f049660797491968aebf9118db9fd",
              'Content-Range' => 'bytes 6-13/14'

    assert_equal "202", res.code, "#{res.code} #{res.body}"
    assert_equal "914e861a274f049660797491968aebf9118db9fd", res.header["X-SHA1"]  #SHA-1 of 'PartOnePartTwo'

    params = CGI::parse(res.body)
    assert_equal ["914e861a274f049660797491968aebf9118db9fd"], params['sha1']
  end


end