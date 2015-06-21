Configuration and install instructions:

The standard location for webwork directories are at `/opt/webwork`.  Adjustments
to these instructions need to be made if that is not true in your case.

* Download the software and make a local copy of the configuration file 

        cd /opt/webwork   
        git clone https://github.com/openwebwork/opaque_server.git 
        cd opaque_server/conf`
        cp opaqueserver.apache-config.dist opaqueserver.apache-config 

* Add the line  
 
         Include /opt/webwork/opaque_server/conf/opaqueserver.apache-config
to the end of the file `/opt/webwork/webwork2/conf/webwork.apache2.4-config`
(or to `webwork.apache2-config`  for  installations using `apache2` but not `apache2.4`)

* The segment called `WeBWorKSOAP` needs to be uncommented.  The Opaque server uses SOAP to
communicate with the main server.

* Rewrite the line `my $hostname = 'http://localhost';` in `opaqueserver.apache-config`
so that `$hostname` is assigned the correct url for your site.

* If WeBWorK is set up in the standard way with directories 
`/opt/webwork/webwork2` and `/opt/webwork/pg` then the paths to those 
directories do not need to be changed. Otherwise other adjustments may be needed
in `opaqueserver.apache-conf`.

* Restart the apache server (after modifying `opaqueserver.apache-conf` if needed).

* You may need to load the cpan module `Memory::Usage.pm`

         cpan Memory::Usage

The main code repo for opaque_server 
has moved to the `github.com/openwebwork` 
site from `github.com/mgage`. 

The current stable code for this feature is now in the branch `master` on   `github.com/openwebwork`.