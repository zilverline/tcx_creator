class Array
  def average
    self.reduce(:+).to_f/self.length
  end
end

class HRM_Recording
  attr_accessor :distance, :ascent, :total_time, :average_altitude, :max_altitude, :average_speed, :max_speed, :start, :has_speed, :has_cadence, :has_altitude, :has_power, :european_format, :exercise_length, :interval, :hrm_data

  DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

  def fix_heart_rate!
    hr_data = hrm_data.map { |m| m.hr }
    average = hr_data.average
    hrm_data.each_with_index do |hrm_point, index|
      if out_range(hrm_point.hr, average)
        if index > 0 && index < hrm_data.length-1
          scan = index+1
          while out_range(hrm_data[scan].hr, average) && scan < (hrm_data.length-1)
            scan += 1
          end
          hrm_point.hr = (hrm_data[index-1].hr + hrm_data[scan].hr)/2
        end
      end
    end
    self
  end

  def self.parse_hrm(filename)
    arr = IO.readlines(filename)
    hrm_data = []
    hrm_recording = HRM_Recording.new
    last_block = ''
    trip_line = 0
    start_date = ''
    distance = 0
    index_offset = 0
    arr.each_with_index do |line, index|
      if line.match(/\[(.*)\]/)
        last_block = $1
        index_offset = index+1
      elsif last_block == "Trip" && line.strip.length > 0
        hrm_recording.distance = line.strip.to_f*100 if trip_line == 0
        hrm_recording.ascent= line.strip.to_i if trip_line == 1
        hrm_recording.total_time = line.strip.to_i if trip_line == 2
        hrm_recording.average_altitude = line.strip.to_i if trip_line == 3
        hrm_recording.max_altitude = line.strip.to_i if trip_line == 4
        hrm_recording.average_speed = line.strip.to_f/128 if trip_line == 5
        hrm_recording.max_speed = line.strip.to_f/128 if trip_line == 6
        trip_line += 1
      elsif last_block == "Params" && line.strip.length > 0
        if line.match(/Date=(\d{8})/)
          #Date=20131225
          start_date = $1
        elsif line.match(/StartTime=(\d{2}:\d{2}:\d{2}.\d+)/)
          #StartTime=13:46:08.0
          hrm_recording.start = DateTime.parse(start_date+" "+$1+"+02:00:00")
        elsif line.match(/Length=(\d{2}:\d{2}:\d{2}.\d+)/)
          #Length=00:56:23.10
          hrm_recording.exercise_length = $1
        elsif line.match(/Interval=(\d+)/)
          #Interval=1
          hrm_recording.interval = $1.to_i
        elsif line.match(/SMode=([0|1]+)/)
          #SMode=11111110
          hrm_recording.has_speed = ($1[0].to_i == 1)
          hrm_recording.has_cadence = ($1[1].to_i == 1)
          hrm_recording.has_altitude = ($1[2].to_i == 1)
          hrm_recording.has_power = ($1[3].to_i == 1)
          hrm_recording.european_format = ($1[7].to_i == 0)
        end
      elsif last_block == "HRData" && line.strip.length > 0
        #print ['\\', "/", '-', '|'].sample
        #sleep 0.001
        #print "\b"
        line_data = line.split(' ')
        hrm_dataline = HRM_DataLine.new
        hrm_dataline.hr = line_data[0].to_i
        hrm_dataline.speed = line_data[1].to_f/10
        hrm_dataline.distance = distance + hrm_dataline.speed * 1000 / 60 / 60 * hrm_recording.interval
        distance = hrm_dataline.distance
        hrm_dataline.cadence = line_data[2].to_i if hrm_recording.has_cadence
        hrm_dataline.altitude = line_data[3].to_i
        hrm_dataline.power = line_data[4].to_i if hrm_recording.has_power
        hrm_dataline.tick = index - index_offset
        hrm_dataline.time = hrm_recording.start+ Rational(hrm_dataline.tick, 24*60*60)
        hrm_data << hrm_dataline
      else
        #puts line if line.strip.length > 0
      end
    end
    hrm_recording.hrm_data = hrm_data
    hrm_recording
  end

  def generate_tcx
    buffer = ""
    xml = Builder::XmlMarkup.new(target: buffer, :indent => 2)
    xml.instruct! :xml, :encoding => "UTF-8"
    xml.TrainingCenterDatabase("xmlns" => "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2", "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance", "xsi:schemaLocation" => "http://www.garmin.com/xmlschemas/TrainingCenterDatabase/v2 http://www.garmin.com/xmlschemas/TrainingCenterDatabasev2.xsd") do |_|
      xml.Activities do |_|
        xml.Activity("Sport" => "Biking") do |s|
          s.Id start.strftime(DATE_FORMAT)
          xml.Lap("StartTime" => start.strftime(DATE_FORMAT)) do |l|
            l.TotalTimeSeconds total_time
            l.Intensity "Active"
            l.Calories 0
            l.TriggerMethod 'Manual'
            l.DistanceMeters distance
            xml.Track do |_|
              hrm_data.each do |hrm_dataline|
                hrm_dataline.generate_tcx(xml)
              end
            end
          end
        end
      end
    end
    buffer
  end

  def stats_report
    "#{hrm_data.length} measurements parsed, TRAINING started at #{start.strftime("%a %F %R, %Z")}: #{distance/1000}km for a duration of #{exercise_length} (#{total_time}seconds) Average Speed: #{average_speed.round(2)}km/h Max Speed: #{max_speed.round(2)}km/h. Ascent: #{ascent}, Average Altitude: #{average_altitude}, Max Altitude: #{max_altitude}."
  end

  private
  def out_range(val, average)
    variation = 0.4
    lower_bound = average*(1-variation)
    upper_bound = average*(1+variation)
    val < lower_bound || val > upper_bound
  end

end