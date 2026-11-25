#!/usr/bin/ruby
# Pipe powermetrics stdout here as the logged-in user. Keep only the last complete interval.
require 'fileutils'
require 'tempfile'

cache = File.expand_path('~/Library/Caches')
destination = File.join(cache, 'eu.exelban.Stats-intel-cpu.txt')
FileUtils.mkdir_p(cache)
sample = []
STDIN.each_line do |line|
  if line.start_with?('*** Sampled system activity')
    if sample.any?
      Tempfile.create('stats-intel-cpu-', cache) do |file|
        file.write(sample.join)
        file.flush
        File.rename(file.path, destination)
      end
    end
    sample.clear
  elsif line.match?(/\A(?:System Average frequency|Intel energy model derived package power|Frequency headroom limited|CPU LIMIT |Core \d+ C-state residency:|CPU Average frequency|\*{4})/)
    sample << line
  end
end
