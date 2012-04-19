require 'httparty'
require 'nokogiri'

class Cruisecontrolrb
  
  include HTTParty
  
  def initialize base_url, username = nil, password = nil
    @auth = { :username => username, :password => password }
    @base_url = base_url
  end
   
  def fetch
    options = { :basic_auth => @auth }

    noko = Nokogiri::XML(self.class.get("http://#{@base_url}/XmlStatusReport.aspx", options).parsed_response)

    return {} unless noko.search("Project").first
    
    # Loop thru projects and construct array of hashes
    noko.search("Project").inject([]) do |projects_array, project|
  
      status_hash = project.attributes.values.inject({}) do |status_hash, attribute| 
        status_hash[attribute.name.to_sym] = attribute.value
        status_hash
      end
        
      link_text = status_hash[:activity] == "Building" ? "build" : status_hash[:lastBuildStatus]
      
      url = status_hash[:webUrl].gsub("projects", "builds") rescue "unknown"
      
      status_hash[:link_to_build] = "<a href=\"" + url + "/" + status_hash[:lastBuildLabel] + 
        "\">" + link_text + "</a>"
        
      projects_array << status_hash
      projects_array
    end
  end
  
end