#!/usr/bin/env ruby

require './test_helper'

# Test and examples of file_storage_handler use.
# That handler doesn't communicate with any backend
#
# Copyright (C) 2013 Piotr Gaertig

class FileStorageUploadTest < Test::Unit::TestCase

  attr_accessor :http, :req

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @http.set_debug_output $stderr if $VERBOSE
    @req = Net::HTTP::Put.new 'http://localhost:8088/upload/resumable'
    @upload_path = "/tmp"
  end

  def test_generates_session_id_for_one_shot
    req.body = "Part1"

    res = http.request(req)
    assert_equal "201", res.code
    assert_equal "0-4/5", res.body
    assert_match /^[a-z0-9]{40}$/, res.header["X-Session-Id"]  #check generated session Id
  end

  def test_fails_when_no_session_id_for_next_chunk
    req.body = "Part1"
    req['content-range'] = 'bytes 0-4/10'
    res = http.request(req)

    assert_equal "201", res.code
    assert_equal "0-4/10", res.body
    session_id = res.header["X-Session-Id"]
    assert_match /^[a-z0-9]{40}$/, session_id  #check generated session Id

    assert_file_content session_id, 'Part1'

    #part2 goes
    req.body = "Part2"
    req['content-range'] = 'bytes 5-9/10'
    res = http.request(req)

    assert_equal "412", res.code
    assert_equal "Session-id is required for chunked upload.", res.body
    assert_nil res.header["X-Session-Id"]  #nothing generated

  end

  def test_generates_session_id_for_first_chunk
    req.body = "Part1"
    req['content-range'] = 'bytes 0-4/10'

    res = http.request(req)
    assert_equal "201", res.code
    assert_equal "0-4/10", res.body
    assert_match /^[a-z0-9]{40}$/, res.header["X-Session-Id"]  #check generated session Id
  end


  #This is example of single chunk upload
  def test_without_content_range

    req.body = "Part1"
    req['session-id'] = '12345'
    res = @http.request(req)

    assert_equal "201", res.code
    assert_equal "0-4/5", res.body
  end

  def test_valid_range_single_part
    assert_new_file '12345', "OnlyOnePart" do
      req.body = "OnlyOnePart"
      req['session-id'] = '12345'
      req['content-range'] = 'bytes 0-10/11'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-10/11", res.body
    end
  end

  def test_range_does_not_match_content_length
    assert_no_file '12345' do
      req.body = "OnlyOnePart"
      req['session-id'] = '12345'
      req['content-range'] = 'bytes 0-109/110'
      res = http.request(req)

      assert_equal "412", res.code
      assert_equal "Range size does not match Content-Length (109-0/110 vs 11)", res.body
    end
  end

  def test_two_parts
    assert_new_file '12345', "Part1Part2" do
      req.body = "Part1"
      req['session-id'] = '12345'
      req['content-range'] = 'bytes 0-4/10'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-4/10", res.body

      assert_file_content '12345', 'Part1'

      #part2 goes
      req.body = "Part2"
      req['content-range'] = 'bytes 5-9/10'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-9/10", res.body
    end
  end

  def test_empty_upload
    assert_new_file '100', "" do
      req.body = ""
      req['session-id'] = '100'
      req['content-range'] = 'bytes 0-0/0'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-0/0", res.body
    end
  end

  def test_empty_upload_without_range
    req.body = nil
    req['session-id'] = '12345'
    res = http.request(req)

    assert_equal "201", res.code
    assert_equal "0-0/0", res.body
  end

  def test_one_byte_body_without_range
    req.body = "X"
    req['session-id'] = '12345'
    res = http.request(req)

    assert_equal "201", res.code
    assert_equal "0-0/1", res.body
  end

  def test_one_byte_body
    req.body = "X"
    req['session-id'] = '12345'
    req['content-range'] = 'bytes 0-0/1'
    res = http.request(req)

    assert_equal "201", res.code
    assert_equal "0-0/1", res.body
  end

  def test_no_chunk_skipping
    assert_new_file '12345', "Part1" do
      req.body = "Part1"
      req['session-id'] = '12345'
      req['content-range'] = 'bytes 0-4/15'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-4/15", res.body

      assert_file_content '12345', 'Part1'

      #part2 is missing and part3 goes
      req.body = "Part3"
      req['content-range'] = 'bytes 10-14/15'
      res = http.request(req)

      #only part1 should remain
      assert_equal "409", res.code
      assert_equal "0-4/15", res.body
    end
  end

  def test_no_random_chunk_first
    assert_no_file '12345' do
      #part1 and 2 are missing and part3 goes
      req.body = "Part3"
      req['session-id'] = '12345'
      req['content-range'] = 'bytes 10-14/15'
      res = http.request(req)

      #nothing on server
      assert_equal "409", res.code
      assert_equal "0-0/0", res.body
    end
  end

  def test_alternative_headers
    assert_new_file '12346', "Only" do
      req.body = "Only"
      req['x-session-id'] = '12346'
      req['x-content-range'] = 'bytes 0-3/11'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-3/11", res.body
    end
  end

  def test_bigger_file_at_once
    assert_new_file 'big10001', "Big" * 10001 do
      #30003 bytes file should be divided by socket receiving logic
      req.body = "Big" * 10001
      req['x-session-id'] = 'big10001'
      req['x-content-range'] = 'bytes 0-30002/30003'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-30002/30003", res.body
    end
  end

  def test_bigger_file_in_2_parts
    assert_new_file 'big2part', "Big" * 10001 + "Small" * 1001 do
      #30003 + 5005 = 35008
      req.body = "Big" * 10001
      req['x-session-id'] = 'big2part'
      req['x-content-range'] = 'bytes 0-30002/35008'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-30002/35008", res.body

      assert_file_content 'big2part', 'Big' * 10001

      req.body = "Small" * 1001
      req['x-session-id'] = 'big2part'
      req['x-content-range'] = 'bytes 30003-35007/35008'
      res = http.request(req)

      assert_equal "201", res.code
      assert_equal "0-35007/35008", res.body
    end
  end
end
