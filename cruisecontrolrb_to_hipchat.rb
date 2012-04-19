require "sinatra/base"
require "./cruisecontrolrb"
require "./hipchat"

class CruisecontrolrbToHipchat < Sinatra::Base
    
  attr_accessor :last_known_projects, :idle_interval, :refresh_interval, :polling_interval
  
  scheduler = Rufus::Scheduler.start_new
  
  @last_known_projects = {}
  
  @idle_interval = ENV['CC_BUILD_IDLE_INTERVAL'].nil? ? 1 * 24 * 60 * 60 : ENV['CC_BUILD_IDLE_INTERVAL'].to_i
  @refresh_interval = ENV['HC_REFRESH_INTERVAL'].nil? ? 1 * 60 * 60 : ENV['HC_REFRESH_INTERVAL'].to_i
  @polling_interval = "#{ENV["POLLING_INTERVAL"] || 1}m"

  scheduler.every(@polling_interval) do  
    begin
      status_hash_array = Cruisecontrolrb.new(ENV["CC_URL"], ENV["CC_USERNAME"] || "", ENV["CC_PASSWORD"] || "").fetch


      status_hash_array.each do |status_hash|
        
        message = ""

        unless status_hash.empty?        

          last_project = @last_known_projects[status_hash[:name]]
          last_status, last_activity, sent_on = last_project.nil? ? [nil, nil, nil] : [last_project[:activity], last_project[:status], last_project[:sent_on]]

          if status_hash[:activity] == "Building" and last_activity != "Building"
            message << "CruiseControl has started a build #{status_hash[:name]}:+#{status_hash[:link_to_build]}."
            color = "yellow"
          # there might be a more clever way to structure this.
          elsif last_project.nil?  
            message << "Detected a new build #{status_hash[:name]} with a current status:+#{status_hash[:link_to_build]}"          
          elsif last_activity == "Building" and status_hash[:activity] != "Building"                   
            message << "The build #{status_hash[:name]} has changed the status:+#{status_hash[:link_to_build]}"          
          elsif last_activity == status_hash[:activity] and last_status == status_hash[:status] and (Time.now - sent_on) > @idle_interval
            message << "The build #{status_hash[:name]} has NOT changed the status +#{status_hash[:link_to_build]} since #{sent_on.to_s}. Maybe you should remove it?}"            
          elsif (Time.now - sent_on) > @refresh_interval
            message << "The build #{status_hash[:name]} is currenty #{status_hash[:activity]} and has a status:+#{status_hash[:link_to_build]}"            
          end
        end

        color = status_hash[:lastBuildStatus] == "Success" ? "green" : "red" unless color == "yellow"

        Hipchat.new.hip_post  message, color unless message == ""

        status_hash[:sent_on] = Time.now
        @last_known_projects[status_hash[:name]] = status_hash

        message
      end
    rescue Exception => e
        Hipchat.new.hip_post "Error occured polling Cruise Control at #{ENV["CC_URL"]}", color     
    end     
  end
  
  get "/" do
    "howdy!"
  end
end