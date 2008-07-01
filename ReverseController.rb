#
#  ReverseController.rb
#  CocoaReverse2
#
#  Created by FreedomCoder on 3/6/08.
#  Copyright (c) 2008 Matias P. Brutti - http://www.freedomCoder.com.ar. All rights reserved.
#
require 'net/http'
require 'rexml/document'
require 'resolv'
require 'osx/cocoa'
require 'ftools'


OSX.require_framework "Webkit"

class ReverseController < NSObject

	ib_outlets	:seachButton, :textField, :fileName, :listOfIPs, :whoisfield, :progress, :files, :webpreview, :tabs 
	ib_outlets	:toolbar_but, :start_button, :stop_button, :whois_button, :preview_button
	Thread.abort_on_exception = false
	
	def init
		if super_init
			@objects = NSMutableArray.array
			check_data
			return self
		end
	end
	
	######## ACTIONS #########
	
	#Action to add an entry
	ib_action :add do |sender|
		@objects.addObject(VirtualDomain.alloc.init('IP address', 'URL','Added by Hand'))
		@listOfIPs.reloadData
		NSLog("Row Added")
	end
	
	#Action to delete an entry
	ib_action :delete do |sender|
		begin
			idx = @listOfIPs.selectedRow
			if @objects.count == 1
				@objects.removeAllObjects
				@listOfIPs.reloadData
			elsif idx < (@objects.count - 1)
				NSRunAlertPanel("Ups...", "You Should Select a row to deleted", nil,nil, nil)
			else
				@objects.removeObjectAtIndex(idx)
				@listOfIPs.selectRow_byExtendingSelection(@objects.count - 1, false)
				@listOfIPs.reloadData
				NSLog("Selected Row Deleted")
			end
		rescue e
			NSRunAlertPanel("Error Message:", e.message, nil,nil, nil)
		end
	end	
	
	#Action to clean all data for new search
	ib_action :newsearch do |sender|
		unless @objects.empty?
			@objects.removeAllObjects
			@listOfIPs.reloadData
		end
	end
	
	#Action to perform a whois on IP, the actual work is perform in resolv_fun
	ib_action :show_whois do |sender|
		begin
			if @objects.empty?
				NSLog("Action on Empty")
				NSRunAlertPanel("Ups...","You should at least have 1 result", nil,nil, nil)
			elsif (@objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('IP').to_s.match('\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b')) != nil
				@progress.startAnimation(sender)
				@whoisfield.setStringValue(resolv_fun(@objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('URL').to_s))
				@progress.stopAnimation(sender)
			elsif @objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('IP').to_s == "IP address"
				NSLog("New Item cannot perform whois")
				NSRunAlertPanel("Ups...","This is a new item with no Data", nil,nil, nil)
			end
		rescue NSException
			NSRunAlertPanel("Error Message:", e.message, nil,nil, nil)
		end
	end
	
	#Action to preview an url in a webkit frame
	ib_action :preview_url do |sender|
		begin
				if @objects.empty?
				NSLog("Action on Empty")
				NSRunAlertPanel("Ups.","You should at least have 1 result", nil,nil, nil)
			elsif @objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('URL').to_s == "URL"
				NSLog("New Item cannot perform preview")
				NSRunAlertPanel("Ups.","This is a new item with no Data", nil,nil, nil)
			else
				@progress.startAnimation(sender)
				@webpreview.mainFrame.loadRequest(NSURLRequest.requestWithURL(NSURL.URLWithString(@objects.objectAtIndex(@listOfIPs.selectedRow).properties.objectForKey('URL').to_s)))
				@progress.stopAnimation(sender)
			end
		rescue NSException
			NSRunAlertPanel("Error Message:", e.message, nil,nil, nil)
		end
	end
	
	#Action to Stop the current search
	ib_action :stop do |sender|
		if defined? @t == nil
			NSRunAlertPanel("Ups..", "Nothing to stop", nil, nil, nil)
		else
			@t.each {|x| x.terminate!}
			@progress.stopAnimation(sender)
		end
	end
	
	#Action to Open file/s
	ib_action :openiplist do |sender|
		oPanel = NSOpenPanel.openPanel
		oPanel.setTitle("Open file/s with IP lists")
		oPanel.setFloatingPanel(true)
		oPanel.setCanChooseFiles(true)
		oPanel.setCanChooseDirectories(false)
		buttonClicked = oPanel.runModal
		
		if buttonClicked == NSOKButton
			@files = oPanel.filenames
			NSLog("Lists of Files loaded")
		end
	end
	
	#Action to Save Results to file
	ib_action :saveiplist do |sender|
		if @objects.empty?
			NSRunAlertPanel("Ups...", "Nothing to save", nil,nil, nil)
		else
			sPanel = NSSavePanel.savePanel
			sPanel.setTitle("Save Results to file")
			sPanel.setExtensionHidden false
			sPanel.setAccessoryView @fileTypeView

			filename = NSString.alloc.initWithString("Untitled.txt")

			buttonClicked = sPanel.runModal
			if buttonClicked == NSOKButton
				oFile = File.new(sPanel.filename, "w+")		
				for idx in 0..@objects.count - 1
					oFile << @objects.objectAtIndex(idx).properties.objectForKey('IP').to_s + ',' +
							 @objects.objectAtIndex(idx).properties.objectForKey('URL').to_s  + ',' +
							 @objects.objectAtIndex(idx).properties.objectForKey('RESULT').to_s + "\n"
				end
				oFile.close
			end
		end
	end
		
	#Action to search this action calls another method that do the works dosearch
	ib_action :search do |sender|
		if @textField.stringValue.empty?
			NSRunAlertPanel("Ups.","You should at least enter an IP addres", nil,nil, nil)
		else
			dosearch(sender)
		end
	end

	########### METHODS #############
	
	#Method that checks for data before loading application.
	def check_data
	dirname  = ENV['HOME'] + "/Library/Application\ Support/CocoaReverse"
	filename  = "objects.temp"
	temp = []
		File.makedirs dirname unless  File.directory?(dirname)
		if File.file? dirname + '/' + filename
			panel = NSRunAlertPanel("Recover data","We found some information not saved for some unknown reason.\nWould you Like to recover the data", "Close" ,"Cancel", "OK")
			case panel
		    when NSAlertOtherReturn
				@tempFile = File.new(dirname + '/' + filename)
				@tempFile.each_line {|line|
					temp = line.split(',')
					@objects.addObject(VirtualDomain.alloc.init(temp[0],temp[1],temp[2]))
				}
				@listOfIPs.reloadData
			  when NSAlertAlternateReturn
				system("rm #{dirname}/#{filename}")
				@tempFile = File.new(dirname + '/' + filename, "w+")
			  else
			    #This else should never happen but WTF just in case ...
			    system("rm #{dirname}/#{filename}")
				  @tempFile = File.new(dirname + '/' + filename, "w+")
			end
		else
			@tempFile = File.new(dirname + '/' + filename, "w+")
		end
	end
	
	#Method that does the the search through the XML response
	def dosearch(sender)
		@headers = {'Cookie' => 'MUID=F67EF0AF11B49D0B9BED154B741157A; ANON=A=50F256A39769555C1C3F9573FFFFFFFF&E=5dd&W=1; NAP=V=1.5&E=583&C=qxy_xe02gLSZHnkAeyINiycykLwDQj8d2p_qT_75BTpM5knjCz3wnA&W=1; frm=true; start_session=128ab7be-3184-4555-ac4f-52dd21e326ad128ab7be-3184-4555-ac4f-52dd21e326ad; mktstate=E=en-US; mkt1=en-US; s_cc=true; s_sq=msnportallive%3D%2526pid%253Dportal%25253Alive.com%25257CSettings%2526pidt%253D1%2526oid%253Dhttp%25253A//search.live.com/settings.aspx%2526ot%253DA%2526oi%253D90; paa=true; SRCHUID=V=1&GUID=2E73E34525FE4CA3B6A9B0C0330660CC; AFORM=LIVSOP; SRCHUSR=AUTOREDIR=0&GEOVAR=-1&DOB=20070814; SFORM=NOFORM; SRCHSESS=GUID=AB34F972E6FC4690B9B0B8F96A61CF6E&TS=1187223946; culture=a=en-US; SRCHHPGUSR=NEWWND=0&ADLT=DEMOTE&NRSLT=50&NRSPH=1&LOC=LAT%3d-34.60|LON%3d-58.45|DISP%3dbuenos%20aires%2c%20distrito%20federal&SRCHLANG=', 'Host' => 'search.live.com'}
		@ips = []
		@ips = create_list()
		@progress.startAnimation(sender)
		@t = []
		
		@ips.each do |i|
			if i.match('\b(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\b') != nil
				@t << Thread.new(i) do |ip|
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
							print_ip(u, ip) # write results to table
						}
					end
				end
				@progress.stopAnimation(sender) if @ips.last == i
			else
				NSRunAlertPanel("Ups...", "This is not an IP #{i} and will not be processed", nil, nil, nil)
			end
		end
	end
	
	#This method creates the list of IPs to search from app field and files if provided.
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
	
	#This method tries to confirm the URL founds.
	def print_ip(myX, ip)
		begin
			if Resolv.getaddress(myX[/http.*:\/\/[._0-9A-Za-z-]*/].split('//')[1]) == ip
				NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed'
				@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed' ))
			else
				http = Net::HTTP.new(ip, 80)
				res, data = http.get("/", {'host' => "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/].split("//")[1]}"})
				case res
					when Net::HTTPSuccess, Net::HTTPRedirection
						if data.match(/Seeing this instead of the website you expected\?/) != nil
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET, with an Apache default installation page'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET, with an Apache default installation page'))
						elsif data.match(/The site you are trying to view does not currently have a default page\./)
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET, with an IIS default installation page'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET, with an IIS default installation page'))
						elsif data.match(/Red Hat Enterprise Linux Test Page/)
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET, with an Red Hat Enterprise Apache  default installation page'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET, with an Red Hat Enterprise Apache default installation page'))
						end
						x = myX.split(/http:\/\//)[1].split('.')
						if x.size == 3
							if data.match(x[1]) != nil
								NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and parse match'
								@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET and parse match'))
							else
								NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and without match'
								@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET without match'))
							end
						elsif x.size == 2
							if data.match(x[0]) != nil
								NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and parse match'
								@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET and parse match'))
							else
								NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and without match'
								@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET without match'))
							end
						else
							NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET'
							@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET'))
						end					
					else
					unless myX.split(/http.*:\/\/[._0-9A-Za-z-]*/)[1] == nil
						res2, data = http.get("#{myX.split(/http.*:\/\/[._0-9A-Za-z-]*/)[1]}", {'host' => "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/].split("//")[1]}"})
						case res2
							when Net::HTTPSuccess, Net::HTTPRedirection
							x = myX.split(/http:\/\//)[1].split('.')
							if x.size == 3
								if data.match(x[1]) != nil
									NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and parse match'
									@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET and parse match'))
								else
									NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and without match'
									@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET without match'))
								end
							elsif x.size == 2
								if data.match(x[0]) != nil
									NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and parse match'
									@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET and parse match'))
								else
									NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET and without match'
									@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET without match'))
								end
							else
								NSLog '   ' + myX[/http.*:\/\/[._0-9A-Za-z-]*/] +  '     ' + 'Confirmed with GET'
								@objects.addObject(VirtualDomain.alloc.init(ip, "#{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}",'Confirmed with GET'))
							end
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
			NSRunAlertPanel("Resolv Error", "Something went wrong while resolving : #{myX[/http.*:\/\/[._0-9A-Za-z-]*/]}", nil,nil, nil)
		end
		@listOfIPs.reloadData
	end
	
	#Method that retrieves the whois data from the resolv.
	def resolv_fun(url)
		begin
			dns =  Resolv::DNS.new
			domain = url.split('//')[1]
			text = "WHOIS for #{url.split('//')[1]}\n"
			text += "NS:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::NS) do |nameserver|
				text += '   ' +nameserver.name.to_s + "\n"
			end
			
			text += "CNAME:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::CNAME) do |nameserver|
				text += '   ' +nameserver.name.to_s + "\n"
			end
			
			text += "SOA:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::SOA) do |nameserver|
				text += '   ' + nameserver.mname.to_s + "\n"
				text += '   ' + nameserver.rname.to_s + "\n"
				text += '   ' + nameserver.serial.to_s + "\n"
				text += '   ' + nameserver.refresh.to_s + "\n"
				text += '   ' + nameserver.retry.to_s + "\n"
				text += '   ' + nameserver.expire.to_s + "\n"
				text += '   ' + nameserver.minimum.to_s + "\n"
			end
			
			text += "HINFO:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::HINFO) do |ip|
				text += '   ' + ip.cpu.to_s + "\n"
				text += '   ' + ip.os.to_s + "\n"
			end
			
			text += "MINFO:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::MINFO) do |ip|
				text += '   ' + ip.rmailbx.to_s + "\n"
				text += '   ' + ip.emailbx.to_s + "\n"
			end
			
			text += "MX:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::MX) do |mail_server|
				text += '   ' + mail_server.preference.to_s + "\n"
				text += '   ' + mail_server.exchange.to_s + "\n"
			end
			
			text += "TXT:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::TXT) do |ip|
				text += '   ' + ip.data.to_s + "\n"
			end
				
			text += "A:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::A) do |ip|
				text += '   ' + ip.address.to_s + "\n"
			end
			
			text += "WKS:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::WKS) do |ip|
				text += '   ' + ip.address.to_s + "\n"
				text += '   ' + ip.protocol.to_s + "\n"
				text += '   ' + ip.bitmap.to_s + "\n"
			end
			
			text += "PTR:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::PTR) do |ip|
				text += '   ' + ip.name.to_s + "\n"
			end
			
			text += "AAAA:\n"
			dns.each_resource(domain, Resolv::DNS::Resource::IN::AAAA) do |ip|
				text += '   ' + ip.address.to_s + "\n"
			end
			return text
		rescue Resolv::ResolvError
			NSRunAlertPanel("Resolv Error:", "Something went wrong while resolving : #{url}", nil,nil, nil)
		end
	end

	#Method for the TableView return amount of rules
	def numberOfRowsInTableView(tableView)
		@objects.count
	end
	
	#Method for the TableView
	def tableView_objectValueForTableColumn_row(tableView, column, row)
		key = column.identifier
		@objects.objectAtIndex(row).properties.objectForKey(key)
	end
	
	#Method for the TableView
    def tableView_setObjectValue_forTableColumn_row(tableView, object, column, row)
		key = column.identifier
		@objects.objectAtIndex(row).properties.setObject_forKey(object, key)
		tableView.reloadData
	end  
	
	#Method for the TableView
	def setUsesAlternatingRowBackgroundColors
		return true
	end
	
	#Method for the TableView
	def tableViewSelectionDidChange(notification)
		if @objects.empty?
			return 0
		else
			@objects.objectAtIndex(@listOfIPs.selectedRow)
		end
	end
end
