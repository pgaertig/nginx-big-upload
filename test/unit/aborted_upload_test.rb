#!/usr/bin/env ruby

require './test_helper'
require 'socket'

# A chunk that breaks mid transfer leaves the storage file open unless on_abort runs. The handler
# pipeline only calls it when the handler exposes it, so this pins the wiring, not the closing.
class AbortedUploadTest < Test::Unit::TestCase

  UPLOAD_PATH = '/tmp'

  def test_aborted_chunk_closes_the_upload_file
    session_id = 'abortedchunk'
    path = File.join(UPLOAD_PATH, session_id)
    File.delete(path) if File.exist?(path)

    socket = start_chunk(session_id, declared: 100_000, sent: 1_000)
    begin
      assert wait_until { open_upload_files.include?(path) },
             "nginx never opened #{path}, the abort path was not reached"
    ensure
      socket.close
    end

    assert wait_until { !open_upload_files.include?(path) },
           "#{path} is still open in an nginx worker after the client went away"
  end

  private

  # Sends the headers and part of the body, then leaves the connection hanging so that the worker
  # sits in socket:receive with the file open.
  def start_chunk(session_id, declared:, sent:)
    socket = TCPSocket.new('localhost', 8088)
    socket.write("POST /upload/resumable HTTP/1.1\r\n" \
                 "Host: localhost\r\n" \
                 "Content-Type: application/octet-stream\r\n" \
                 "Content-Range: bytes 0-#{declared - 1}/#{declared}\r\n" \
                 "Session-Id: #{session_id}\r\n" \
                 "Content-Length: #{declared}\r\n\r\n")
    socket.write('x' * sent)
    socket.flush
    socket
  end

  def wait_until(timeout = 5.0)
    deadline = Time.now + timeout
    until Time.now > deadline
      return true if yield

      sleep 0.05
    end
    false
  end

  def open_upload_files
    nginx_worker_pids.flat_map do |pid|
      Dir.children("/proc/#{pid}/fd").filter_map do |fd|
        File.readlink("/proc/#{pid}/fd/#{fd}") rescue nil
      end
    end
  rescue SystemCallError
    []
  end

  def nginx_worker_pids
    Dir['/proc/[0-9]*/cmdline'].filter_map do |cmdline|
      next unless (File.read(cmdline) rescue '').start_with?('nginx: worker process')

      File.basename(File.dirname(cmdline)).to_i
    end
  end
end
