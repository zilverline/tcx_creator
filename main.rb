#!/usr/bin/ruby
require 'date'
require 'rational'
require 'builder'



class Array
  def average
    self.reduce(:+).to_f/self.length
  end
end

DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

def parse_hrm(filename)
  arr = IO.readlines(filename)
  hrm_data = []
  meta_data = {}
  last_block = ''
  block_line = 0
  start_date = ''
  distance = 0
  arr.each_with_index do |line, index|
    if line.match(/\[(.*)\]/)
      last_block = $1
    elsif last_block == "Trip" && line.strip.length > 0
      meta_data[:distance] = line.strip.to_f*100 if block_line == 0
      meta_data[:ascent] = line.strip.to_i if block_line == 1
      meta_data[:total_time] = line.strip.to_i if block_line == 2
      meta_data[:average_altitude] = line.strip.to_i if block_line == 3
      meta_data[:max_altitude] = line.strip.to_i if block_line == 4
      meta_data[:average_speed] = line.strip.to_f/128 if block_line == 5
      meta_data[:max_speed] = line.strip.to_f/128 if block_line == 6
      block_line += 1
    elsif last_block == "Params" && line.strip.length > 0
      if line.match(/Date=(\d{8})/)
        #Date=20131225
        start_date = $1
      elsif line.match(/StartTime=(\d{2}:\d{2}:\d{2}.\d+)/)
        #StartTime=13:46:08.0
        meta_data[:start] = DateTime.parse(start_date+" "+$1)
      elsif line.match(/Length=(\d{2}:\d{2}:\d{2}.\d+)/)
        #Length=00:56:23.10
        meta_data[:exercise_length] = $1
      elsif line.match(/Interval=(\d+)/)
        #Interval=1
        meta_data[:interval] = $1.to_i
      elsif line.match(/SMode=([0|1]+)/)
        #SMode=11111110
        meta_data[:speed] = ($1[0].to_i == 1)
        meta_data[:cadence] = ($1[1].to_i == 1)
        meta_data[:altitude] = ($1[2].to_i == 1)
        meta_data[:power] = ($1[3].to_i == 1)
        meta_data[:euro] = ($1[7].to_i == 0)
      end
    elsif last_block == "HRData" && line.strip.length > 0
      print '.'
      line_data = line.split(' ')
      hr_line = {}
      hr_line[:hr] = line_data[0].to_i
      hr_line[:speed] = line_data[1].to_f/10
      hr_line[:distance] = distance + hr_line[:speed] * 1000 / 60 / 60 * meta_data[:interval]
      distance = hr_line[:distance]
      hr_line[:cadence] = line_data[2].to_i if meta_data[:cadence]
      hr_line[:altitude] = line_data[3].to_i
      hr_line[:power] = line_data[4].to_i  if meta_data[:power]
      hr_line[:time] = meta_data[:start]+ Rational(index, 24*60*60)
      hrm_data << hr_line
    else
      #puts line if line.strip.length > 0
    end
  end
  return hrm_data, meta_data
end

def out_range(val, average)
  variation = 0.4
  lower_bound = average*(1-variation)
  upper_bound = average*(1+variation)
  val < lower_bound || val > upper_bound
end

def fix_heart_rate(hrm_data)
  hr_data = hrm_data.map { |m| m[:hr] }
  average = hr_data.average
  hrm_data.each_with_index do |hrm_point, index|
    if out_range(hrm_point[:hr], average)
      print '+'
      if index > 0 && index < hrm_data.length-1
        scan = index+1
        while out_range(hrm_data[scan][:hr], average) && scan < (hrm_data.length-1)
          scan += 1
        end
        hrm_point[:hr] = (hrm_data[index-1][:hr] + hrm_data[scan][:hr])/2
      end
    end
  end
  hrm_data
end

def generate_tcx(meta_data, hrm_data)
  buffer = ""
  xml = Builder::XmlMarkup.new(target: buffer, :indent => 2)
  xml.instruct! :xml, :encoding => "UTF-8"
  xml.TrainingCenterDatabase("xmlns" => "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:schemaLocation" => "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd") do |_|
    xml.Activities do |_|
      xml.Activity("Sport" => "Biking") do |s|
        s.Id meta_data[:start].strftime(DATE_FORMAT)
        xml.Lap("StartTime" => meta_data[:start].strftime(DATE_FORMAT)) do |l|
          l.TotalTimeSeconds meta_data[:total_time]
          l.Intensity "Active"
          l.Calories 0
          l.TriggerMethod 'Manual'
          l.DistanceMeters meta_data[:distance]
          xml.Track do |_|
            hrm_data.each_with_index do |hrm_point, index|
              xml.Trackpoint do |p|
                p.Time hrm_point[:time].strftime(DATE_FORMAT)
                p.DistanceMeters hrm_point[:distance]
                p.AltitudeMeters hrm_point[:altitude]
                p.HeartRateBpm("xsi:type" => "HeartRateInBeatsPerMinute_t") {
                  p.Value hrm_point[:hr]
                }
                p.Cadence hrm_point[:cadence]
                p.Extensions {
                  p.TPX("xmlns" => "http://www.garmin.com/xmlschemas/ActivityExtension/v2") {
                    p.Watts hrm_point[:power]
                  }
                }
              end
            end
          end
        end
      end
    end
  end
  buffer
end

filenames = ARGV.each
filenames.each do |filename|
  output_file = filename.gsub(/\.hrm/, '.tcx')
  puts "creating #{output_file} based on #{filename}"
  hrm_data, meta_data = parse_hrm(filename)
  p meta_data
  hrm_data = fix_heart_rate(hrm_data)
  target = File.open(output_file, 'w')
  target << generate_tcx(meta_data, hrm_data)
  target.close
  puts ''
  puts "done processing #{hrm_data.length} points"
end