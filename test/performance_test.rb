require './test_helper.rb'
require 'benchmark'

# Compares speed of nginx-big-upload and nginx-upload-module

class PerformanceTest < Test::Unit::TestCase

  attr_accessor :http

  def setup
    @http = Net::HTTP.new 'localhost', 8088
    @upload_path = "/tmp"
    @body512k = "Performant" * 51 * 1024 # ~512KB chunk
  end

  def test_lua_perf
    #51MB
    run_cycle('perflua', 'http://localhost:8088/upload/perf-bu', 100)
  end

#  def test_num_perf
    #51MB
#    run_cycle('perfnum', 'http://localhost:8088/upload/perf-num', 100)
#  end


  def test_final_perf
    n = 10
    Benchmark.bm do |x|
      x.report("bu     51MB * 10") { n.times {
         run_cycle('perfbu', 'http://localhost:8088/upload/perf-bu', 100)
      }}
      x.report("bu_crc 51MB * 10") { n.times {
        run_cycle('perfbu', 'http://localhost:8088/upload/perf-bu-crc', 100)
      }}
#      x.report("num    51MB * 10") { n.times {
#         run_cycle('perfnum', 'http://localhost:8088/upload/perf-num', 100)
#      }}
      x.report("bu    204MB * 10") {n.times {
         run_cycle('perfbu', 'http://localhost:8088/upload/perf-bu', 400)
      }}
#      x.report("num   204MB * 10") {n.times {
#         run_cycle('perfnum', 'http://localhost:8088/upload/perf-num', 400)
#      }}
    end
  end



  def run_cycle(id, uri, chunks_no)
    file = "/tmp/#{id}"
    File.delete(file) if File.exists?(file)
    req = Net::HTTP::Post.new uri
    req.body = @body512k
    req['content-type'] = 'application/octet-stream'
    req['Content-Disposition'] = 'attachment; filename="somename.dat"'
    req['session-id'] = id
    chunk_size = req.body.size
    total_size = chunks_no * chunk_size
    offset = 0
    for chunk in 1..chunks_no
      req['content-range'] = "bytes #{offset}-#{offset+chunk_size - 1}/#{total_size}"
      res = http.request(req)
      if chunk == chunks_no
        assert_equal "202", res.code
        assert_match /path/, res.body
      else
        assert_equal "201", res.code, res.body
      end
      offset += chunk_size
    end

    assert File.exists?(file)
    assert_equal total_size, File.size(file)
    assert_equal 1, File.delete(file)
  end


end