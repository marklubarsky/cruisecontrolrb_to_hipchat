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
          
          last_status, last_activity, changed_on = last_project.nil? ? [nil, nil, nil] : [last_project[:status], last_project[:activity], last_project[:changed_on]]

          if status_hash[:activity] == "Building" and last_activity != "Building"
            message << "CruiseControl has started a build #{status_hash[:name]}:+#{status_hash[:link_to_build]}."
            status_hash[:changed_on] = Time.now
            color = "yellow"
          # there might be a more clever way to structure this.
          elsif last_project.nil?  
            message << "Detected a new build #{status_hash[:name]} with a current status:+#{status_hash[:link_to_build]}"          
            status_hash[:changed_on] = Time.now
          elsif status_hash[:activity] != "Building"  and last_activity == "Building"                 
            message << "The build #{status_hash[:name]} was #{last_activity} and is now #{status_hash[:activity]} and has changed the status:+#{status_hash[:link_to_build]}"          
            status_hash[:changed_on] = Time.now
          elsif !changed_on.nil? and last_activity == status_hash[:activity] and last_status == status_hash[:status] and (Time.now - changed_on) > @idle_interval
            message << "The build #{status_hash[:name]} is still #{status_hash[:activity]} and has NOT changed the status +#{status_hash[:link_to_build]} since #{changed_on.to_s}. Maybe you should remove it?}"            
          elsif !changed_on.nil? and (Time.now - changed_on) > @refresh_interval
            message << "The build #{status_hash[:name]} is currenty #{status_hash[:activity]} and has a status:+#{status_hash[:link_to_build]}"            
            status_hash[:changed_on] = Time.now
          end
        end

        color = status_hash[:lastBuildStatus] == "Success" ? "green" : "red" unless color == "yellow"

        Hipchat.new.hip_post message, color unless message == ""

        @last_known_projects[status_hash[:name]] = status_hash

        message
      end
    rescue Exception => e
        link_to_cc = "<a href='http://#{ENV["CC_URL"]}'>http://#{ENV["CC_URL"]}</a>"        
        Hipchat.new.hip_post "Error occured polling Cruise Control (#{e.message}) at #{link_to_cc}", "red"     
    end     
  end
  
  get "/" do
    "howdy!"
  end
end