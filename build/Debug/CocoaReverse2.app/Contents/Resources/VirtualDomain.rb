class VirtualDomain < NSObject

  kvc_accessor :properties

  def init(ip,url,result)
      @properties = NSMutableDictionary.dictionaryWithObjects_forKeys([ ip, url, result],['IP', 'URL', 'RESULT'])
      return self
  end

end