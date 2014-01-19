class HRM_DataLine
  attr_accessor :hr, :speed, :distance, :cadence, :altitude, :power, :time
  DATE_FORMAT = "%Y-%m-%dT%H:%M:%SZ"

  def generate_tcx(xml)
    xml.Trackpoint do |p|
      p.Time time.strftime(DATE_FORMAT)
      p.DistanceMeters distance
      p.AltitudeMeters altitude
      p.HeartRateBpm("xsi:type" => "HeartRateInBeatsPerMinute_t") {
        p.Value hr
      }
      p.Cadence cadence
      p.Extensions {
        p.TPX("xmlns" => "http://www.garmin.com/xmlschemas/ActivityExtension/v2") {
          p.Watts power
        }
      }
    end
  end
end