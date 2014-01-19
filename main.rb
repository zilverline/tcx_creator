#!/usr/bin/ruby
require 'date'
require 'rational'
require 'builder'

require_relative 'hrm_recording'
require_relative 'hrm_dataline'

filenames = ARGV.each
filenames.each do |filename|
  output_file = filename.gsub(/\.hrm/, '.tcx')
  puts "creating #{output_file} based on #{filename}"
  hrm_recording = HRM_Recording.parse_hrm(filename)
  hrm_recording.fix_heart_rate
  target = File.open(output_file, 'w')
  target << hrm_recording.generate_tcx
  target.close
  puts ''
  puts hrm_recording.stats_report
end