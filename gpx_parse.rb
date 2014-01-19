#!/usr/bin/ruby
require "geokit"
require 'nokogiri'

Geokit::default_units = :kms
Geokit::default_formula = :sphere

class Array
  def average
    self.reduce(:+).to_f/self.length
  end
end

def parse_gpx(filename)
  f = File.open(filename)
  doc = Nokogiri::XML(f)
  doc.remove_namespaces!
  f.close
  doc.xpath("//trkpt").map { |tp|
    {lat_long: Geokit::LatLng.new(tp.xpath("@lat").first.value, tp.xpath("@lon").first.value), alt: tp.xpath("ele").first.content.to_f}
  }
end

def initialize_stats(gpx_data)
  stats = {}
  stats[:gpx_points] = gpx_data.length
  start= gpx_data.first[:lat_long]
  finish= gpx_data.last[:lat_long]
  stats[:start_address] = start.reverse_geocode.full_address
  stats[:finish_address] = finish.reverse_geocode.full_address
  stats[:lowest_elevation] = gpx_data.map { |tp| tp[:alt] }.min
  stats[:highest_elevation] = gpx_data.map { |tp| tp[:alt] }.max
  stats[:average_elevation] = gpx_data.map { |tp| tp[:alt] }.average
  stats[:total_distance]= 0.0
  stats[:total_ascent]= 0.0
  stats[:total_descent]= 0.0
  stats
end

def stats_from_point(gpx_data, index)
  a = gpx_data[index][:lat_long]
  b = gpx_data[index+1][:lat_long]
  h_a = gpx_data[index][:alt]
  h_b = gpx_data[index+1][:alt]
  climb = (h_b - h_a).round(1)
  distance = a.distance_to(b)*1000
  #distance = Math.sqrt((a.distance_to(b)*1000)**(2) + climb**2)
  return distance, climb
end

filenames = ARGV.each
filenames.each do |filename|
  puts "parsing #{filename}"
  gpx_data = parse_gpx(filename)
  stats = initialize_stats(gpx_data)
  distances = []
  gradients = []
  gpx_data[0..-2].each_with_index do |gpx_point, index|
    distance, climb = stats_from_point(gpx_data, index)
    gradients << (distance == 0.0 ? 0 : Math.atan(climb/distance)/Math::PI*4*45)
    stats[:total_ascent] += climb if climb >0
    stats[:total_descent] += -climb if climb <0
    stats[:total_distance] += distance
    distances << distance
  end
  stats[:min_gradient] = gradients.min
  stats[:max_gradient] = gradients.max
  stats[:steepest_point_up] = gradients.find_index(stats[:max_gradient])
  stats[:steepest_point_down] = gradients.find_index(stats[:min_gradient])
  stats[:average_climbing_gradient] = gradients.select { |g| g > 0.0 }.average
  stats[:average_descending_gradient] = gradients.select { |g| g < 0.0 }.average
  p stats
  #p distances
end