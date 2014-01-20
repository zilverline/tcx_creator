require_relative 'spec_helper'

describe "HRM_Recording" do

  it 'parse a file' do
    hrm_recording = HRM_Recording.parse_hrm('spec/fixtures/input.hrm')
    hrm_recording.stats_report.should include "3384"
  end
end


