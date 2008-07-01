#
#  ReverseController.rb
#  CocoaReverse2
#
#  Created by FreedomCoder on 3/6/08.
#  Copyright (c) 2008 __MyCompanyName__. All rights reserved.
#
require 'net/http'
require 'rexml/document'
require 'resolv'
require 'osx/cocoa'

OSX.require_framework "Automator"
OSX.require_framework "Webkit"

class ReverseController < NSObject

	ib_outlets	:seachButton, :textField, :fileName, :listOfIPs, :whoisfield, :progress, :files
		
	def init
		if super_init
			@objects = NSMutableArray.array
			return self
		end
	end
	
	######## ACTIONS #########
	
	ib_action :add do |sender|
		@objects.addObject(VirtualDomain.alloc.init('IP address', 'URL','Added by Hand'))
		@listOfIPs.reloadData
		NSLog("Row Added")
	end
	
	ib_action :newsearch do |sender|
		@objects.removeAllObjects
		@listOfIPs.reload
	end
	
	ib_action :openiplist do |sender|
		
		oPanel = NSOpenPanel.openPanel
		oPanel.setCanChooseFiles(true)
		oPanel.setCanChooseDirectories(false)
		buttonClicked = oPanel.runModal
		
		if buttonClicked == NSOKButton
			@files = oPanel.filenames
			NSLog("Lists of Files loaded")
		end
	end
	
	ib_action :saveiplist do |sender|
		sPanel = NSSavePanel.savePanel
		sPanel.setExtensionHidden false
		sPanel.setAccessoryView @fileTypeView

		filename = NSString.alloc.initWithString("Untitled.txt")

		buttonClicked = sPanel.runModal
		if buttonClicked == NSOKButton
			oFile = File.new(sPanel.filename, "w+")		
			for idx in 0..@objects.count - 1
				oFile << @objects.objectAtIndex(idx).properties.objectForKey('IP').to_s + ',' +
						 @objects.objectAtIndex(idx).properties.objectForKey('URL').to_s  + ',' +
						 @objects.objectAtIndex(idx).properties.objectForKey('RESULT').to_s + '\n'
			end
			oFile.close
		end
	end
	
	ib_action :delete do |sender|
		idx = @listOfIPs.selectedRow
		return if idx < 0
		return if idx < (@objects.count - 1)
		
		@objects.removeObjectAtIndex(idx)
		@listOfIPs.selectRow_byExtendingSelection(@objects.count - 1, false)
		@listOfIPs.reloadData
		NSLog("Selected Row Deleted")
	end	
	
	ib_action :search do |sender|
		if @textField.stringValue.empty?
			NSRunAlertPanel("Ups.","You should at least enter an IP addres", nil,nil, nil)
		else
			NSThread.detachNewThreadSelector_toTarget_withObject(dosearch, @listOfIPs, nil)
		end
	end
	
	ib_action :dosearch do |sender|
		@headers = {'Cookie' => 'MUID=F67EF0AF11B49D0B9BED154B741157A; ANON=A=50F256A39769555C1C3F9573FFFFFFFF&E=5dd&W=1; NAP=V=1.5&E=583&C=qxy_xe02gLSZHnkAeyINiycykLwDQj8d2p_qT_75BTpM5knjCz3wnA&W=1; frm=true; start_session=128ab7be-3184-4555-ac4f-52dd21e326ad128ab7be-3184-4555-ac4f-52dd21e326ad; mktstate=E=en-US; mkt1=en-US; s_cc=true; s_sq=msnportallive%3D%2526pid%253Dportal%25253Alive.com%25257CSettings%2526pidt%253D1%2526oid%253Dhttp%25253A//search.live.com/settings.aspx%2526ot%253DA%2526oi%253D90; paa=true; SRCHUID=V=1&GUID=2E73E34525FE4CA3B6A9B0C0330660CC; AFORM=LIVSOP; SRCHUSR=AUTOREDIR=0&GEOVAR=-1&DOB=20070814; SFORM=NOFORM; SRCHSESS=GUID=AB34F972E6FC4690B9B0B8F96A61CF6E&TS=1187223946; culture=a=en-US; SRCHHPGUSR=NEWWND=0&ADLT=DEMOTE&NRSLT=50&NRSPH=1&LOC=LAT%3d-34.60|LON%3d-58.45|DISP%3dbuenos%20aires%2c%20distrito%20federal&SRCHLANG=', 'Host' => 'search.live.com'}
		@ips = []
		@ips = create_list()
		@progress.startAnimation(sender)
		
		@ips.each do |ip|
			url = 'search.live.com'
			path = '/results.aspx?q=ip:' + ip + '&count=200&format=xml'
			http = Net::HTTP.new(url,80)
			xml_data = http.get(path, @headers).body
			doc = REXML::Document.new(xml_data)
			urls = []
			# check if the IP has more than 200 host
			total = doc.root.elements["documentset[@source='FEDERATOR_MONARCH']"].attributes["total"].to_i()
			if total > 200    # In the case the host has more than 200 do the following.
				NSLog'For IP=' + ip
				doc.elements.each('searchresult/documentset/document/url') do |e|
					urls << e.text
				end
				urls.each { |u|
					print_ip(u, ip) # write results to table
				}
				for first in (201..total)
					path = '/results.aspx?q=ip:' + ip + '&count=200&format=xml' + '&first=' + first.to_s
					xml_data = http.get(path, @headers).body
					doc = REXML::Document.new(xml_data)
					doc.elements.each('searchresult/documentset/document/url') do |e|
						urls << e.text
					end
					print_out(urls, ip)
					first +=200
				end     # end for
			else      # end if
				doc.elements.each('searchresult/documentset/document/url') do |e|
					urls << e.text
				end
				NSLog'For IP=' + ip 
				urls.each { |u|
					@listOfIPs.reloadData
					print_ip(u, ip) # write results to table
				}
			end
		end
		@progress.stopAnimation(sender)
	end
	
	########### METHODS #############
	
	def create_list
		ips=[]
		if @textField.stringValue.to_s != nil
			ips = @textField.stringValue.to_s.split(',')       
		end
		if @files != nil     
			count = @files.count
			for i in 0..count - 1
				aFile = File.new(@files[i].to_s)
				aFile.each_line {|ip|
					ips << ip.split("\n")[0]
				}
				aFile.close
			end
			
		end
		ips
	end
	
	
	def windowWillLoad(notification)
		NSLog "tests windows load"
	end
	
	def windowShouldClose(sender)
		NSLog("not going to close")
	end


	def print_ip(myX, ip)
		begin
			if Resolv.getaddress(myX[/http.*:\/\/[._0-9A-Za-z-]*/].split('//')[1]) == ip
				NSLog'   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed'
				@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed' ))
			else
				http = Net::HTTP.new(ip, 80)
				res, data = http.get("/", {'host' => "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/].split("//")[1]}"})
				case res
					when Net::HTTPSuccess, Net::HTTPRedirection
						NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET'
						@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET'))
					else
					unless myX.split(/http.*:\/\/[._0-9A-Za-z-]*/)[1] == nil
						res2, data = http.get("#{myX.split(/http.*:\/\/[._0-9A-Za-z-]*/)[1]}", {'host' => "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/].split("//")[1]}"})
						case res2
							when Net::HTTPSuccess, Net::HTTPRedirection
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET'))
						else  
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Not confirmed'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Not Confirmed'))
						end
					else
						NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Not confirmed'
						@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Not Confirmed'))
					end
				end
			end
		rescue Resolv::ResolvError
			NSRunAlertPanel("Resolv Error", "Something went working with the Resolv", nil,nil, nil)
		end
		@listOfIPs.reloadData
	end


	def numberOfRowsInTableView(tableView)
		@objects.count
	end

	def tableView_objectValueForTableColumn_row(tableView, column, row)
		key = column.identifier
		@objects.objectAtIndex(row).properties.objectForKey(key)
	end
  
    def tableView_setObjectValue_forTableColumn_row(tableView, object, column, row)
		key = column.identifier
		@objects.objectAtIndex(row).properties.setObject_forKey(object, key)
		tableView.reloadData
	end  
	
	def setUsesAlternatingRowBackgroundColors
		return true
	end
	
	def tableViewSelectionDidChange(notification)
		if @objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('IP').to_s == "IP address"
			NSLog("Whois Not applicable") 
		else
			@whoisfield.setStringValue(resolv_fun(@objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('URL').to_s))
		end
	end
	
	
	def resolv_fun(url)
		dns =  Resolv::DNS.new
		domain = url.split('//')[1]
		text = "WHOIS for #{url.split('//')[1]}\n"
		text += "NS\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::NS) do |nameserver|
			text += '   ' +nameserver.name.to_s + "\n"
		end
		
		text += "CNAME\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::CNAME) do |nameserver|
			text += '   ' +nameserver.name.to_s + "\n"
		end
		
		text += "SOA\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::SOA) do |nameserver|
			text += '   ' + nameserver.mname.to_s + "\n"
			text += '   ' + nameserver.rname.to_s + "\n"
			text += '   ' + nameserver.serial.to_s + "\n"
			text += '   ' + nameserver.refresh.to_s + "\n"
			text += '   ' + nameserver.retry.to_s + "\n"
			text += '   ' + nameserver.expire.to_s + "\n"
			text += '   ' + nameserver.minimum.to_s + "\n"
		end
		
		text += "HINFO\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::HINFO) do |ip|
			text += '   ' + ip.cpu.to_s + "\n"
			text += '   ' + ip.os.to_s + "\n"
		end
		
		text += "MINFO\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::MINFO) do |ip|
			text += '   ' + ip.rmailbx.to_s + "\n"
			text += '   ' + ip.emailbx.to_s + "\n"
		end
		
		text += "MX\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::MX) do |mail_server|
			text += '   ' + mail_server.preference.to_s + "\n"
			text += '   ' + mail_server.exchange.to_s + "\n"
		end
		
		text += "TXT\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::TXT) do |ip|
			text += '   ' + ip.data.to_s + "\n"
		end
			
		text += "A\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::A) do |ip|
			text += '   ' + ip.address.to_s + "\n"
		end
		
		text += "WKS\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::WKS) do |ip|
			text += '   ' + ip.address.to_s + "\n"
			text += '   ' + ip.protocol.to_s + "\n"
			text += '   ' + ip.bitmap.to_s + "\n"
		end
		
		text += "PTR\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::PTR) do |ip|
			text += '   ' + ip.name.to_s + "\n"
		end
		
		text += "AAAA\n"
		dns.each_resource(domain, Resolv::DNS::Resource::IN::AAAA) do |ip|
			text += '   ' + ip.address.to_s + "\n"
		end
	text
	end
end
