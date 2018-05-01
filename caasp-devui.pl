#!/usr/bin/perl -w
use strict;
use CGI;
use CGI::Carp qw(fatalsToBrowser);
use Sys::Virt;
use Data::Dumper;
use YAML;
use JSON::XS qw/decode_json/;
use Net::SSH::Expect;
use XML::Bare qw/forcearray/;
use Archive::Tar;
use File::Slurp;
my $q = new CGI;
print $q->header;
my %vars = $q->Vars;

if( %vars ) {
  for my $key ( keys %vars ) {
    my $val = $vars{ $key };
    #print "Key: $key - Value: $val<br>\n";
  }
}

my $op = $vars{'op'};
if( $op ) {
  if( $op eq 'imageinfo' ) {
    my $id8 = $vars{'id'};
    my $jsoninfo = `docker image inspect $id8`;
    #print Dumper( $jsoninfo );
    my $info = decode_json( $jsoninfo )->[0];
    #print Dumper( $info );
    
    my $id = $info->{'Id'};
    $id =~ s/^.+://;
    print "Id: $id<br>\n";
    
    my $config = $info->{'Config'};
    my $cmds = $config->{'Cmd'};
    for my $cmd ( @$cmds ) {
      print "Cmd: $cmd<br>\n";
    }
    
    my $rootfs = $info->{'RootFS'};
    my $layers = forcearray( $rootfs->{'Layers'} );
    my @lids;
    for my $layer ( @$layers ) {
      $layer =~ s/^.+://;
      #print "Layer: $layer<br>\n";
      #push( @lids, $layer );
    }
    
    print "<a href='?op=imagelayers&id=$id'>View image layers</a><br>";
    print "<a href='?op=imagehistory&id=$id8'>View image history</a>";
    exit;
  }
  if( $op eq 'imagehistory' ) {
    my $id8 = $vars{'id'};
    my $changes = doDocker(
      "history $id8",
      created => "CreatedAt",
      change => "CreatedBy",
      size => "Size",
      comment => "Comment"
    );
    print "Layers:<br><table border=1 cellpadding=6 cellspacing=0><tr><th>When</th><th>Change</th><th>Size</th><th>Comment</th></tr>";
    
    for my $change ( @$changes ) {
      my $created = $change->{'created'};
      my $changeT = $change->{'change'};
      my $size = $change->{'size'};
      my $comment = $change->{'comment'};
      $changeT =~ s/ \&\& /<br>\n/g;
      $changeT =~ s|^/bin/sh -c #\(nop\) |<b>CONF</b> - |g;
      print "<tr><td>$created</td><td>$changeT</td><td>$size</td><td>$comment</td></tr>";
    } 
    print "</table>";
  }
  if( $op eq 'imagelayers' ) {
    my $id = $vars{'id'};
    print "Layers:<br><table border=1 cellpadding=6 cellspacing=0><tr><th>Tar</th><th>File Count</th></tr>";
    
    my $xFolder = "/srv/www/caasp-devui/extracted_docker_images/$id";
    if( -e $xFolder ) {
      #print "Extracted folder exists<br>\n";
      my $manifestFile = "$xFolder/manifest.json";
      if( -e $manifestFile ) {
        my $minfo = decode_json( read_file( $manifestFile ) )->[0];
        my $layers2 = $minfo->{'Layers'};
        for my $tarFileName ( @$layers2 ) {
          my $tarFile = "$xFolder/$tarFileName";
          if( -e $tarFile ) {
            my $tar = Archive::Tar->new();
            $tar->read( $tarFile );
            my @files = $tar->list_files();
            my $num = scalar @files;
            if( $num < 30 ) {
              for my $file ( @files ) {
                #print "$file<br>\n";
              }
            }
            print "<tr><td>$tarFileName</td><td>$num</td></rt>";
            #print "Num files: $num<br>\n";
          }
          else {
            print "$tarFile does not exist<br>\n";
          }
        }
      }
    }
    print "</table>";
    exit;
  }
  if( $op eq 'images' ) {
    my $imgs = doDocker(
      "images",
      id => "ID",
      repo => "Repository",
      size => "Size",
      tag => "Tag"
    );
    print "Images:<br><table border=1 cellpadding=6 cellspacing=0><tr><th>ID</th><th>Repo</th><th>Tag</th><th>Size</th></tr>";
      
    for my $img ( @$imgs ) {
      my $id = $img->{'id'};
      $id =~ s/.+://;
      my $id4 = substr( $id, 0, 4 );
      my $id8 = substr( $id, 0, 8 );
      my $repo = $img->{'repo'};
      my $size = $img->{'size'};
      my $tag = $img->{'tag'};
      print "<tr><td><a href='?op=imageinfo&id=$id8'>$id4</a></td><td>$repo</td><td>$tag</td><td>$size</td></tr>";
    }
    print "</table>";
    exit;
  }
  if( $op eq 'showinit' ) {
    my $file = $vars{'file'};
    if( $file !~ m|^[a-zA-Z0-9_/\.]+$| ) {
      print "Invalid filename<br>";
      exit;
    }
    my $filelistraw = `isoinfo -J -f -i $file`;
    my @files = split( "\n", $filelistraw );
    for my $afile ( @files ) {
      print "File: $afile<br>\n";
      if( $afile =~ m/user-data/ ) {
        my $filedata = `isoinfo -J -x $afile -i $file`;
        
        #$filedata =~ s/^#.+?\n//gs;
        #$filedata =~ s/\n( *\- )(.+?)\n/\n$1'$2'\n/gs;
        #my $hash = readdata( $filedata );
        #print Dumper( $hash );
        #print "SSH Authorized Key: " . $hash->{'ssh_authorized_keys'};
        #print $filedata;
        #my $hash = Load( $filedata );
        #print Dumper( $hash );
        print "Raw file data:<br><textarea style='width: 100\%; height: 500px'>$filedata</textarea>";
      }
    }
    exit;
    #print "Files: $filelist<br>";
  }
  if( $op eq 'dockerps' ) {
    my $domName = $vars{'domain'};
    if( !$domName ) {
      print "Domain must be provided";
      exit;
    }
    my $vmm = Sys::Virt->new(uri => "qemu:///system");
    my $domain = $vmm->get_domain_by_name( $domName );
    if( !$domain ) {
      print "Could not find domain '$domain'";
      exit;
    }
    
    my @nics = $domain->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE);
    my $ip = '';
    for my $nic ( @nics ) {
      my $addrs = $nic->{'addrs'};
      for my $addr ( @$addrs ) {
        $ip = $addr->{'addr'};
      }
    }
    if( !$ip ) {
      print "Could not get IP address of domain '$domName'";
      exit;
    }
    print "IP address of domain '$domName': $ip<br>\n";
    
    my $ssh = Net::SSH::Expect->new(
      host => $ip,
      user => 'root',
      raw_pty => 1,
      ssh_option => '-o StrictHostKeyChecking=no -i /srv/www/caasp-devui/id_shared'
    );
    $ssh->run_ssh() or die "Could not start ssh $!";
    my $login = $ssh->read_all(2);
    print "Login prompt: $login<br>\n";
    if( $login !~ / #/ ) {
      print "where's the remote prompt?";
      exit;
    }
    $ssh->exec("stty raw -echo");
    my $psRaw = $ssh->exec("docker ps --no-trunc --format '<pod><id><![CDATA[{{.ID}}]]></id>\n<cmd><![CDATA[{{.Command}}]]></cmd>\n<names><![CDATA[{{.Names}}]]></names><labels><![CDATA[{{.Labels}}]]></labels></pod>\n'");
    my ( $ob, $simp ) = XML::Bare->simple( text => $psRaw );
    
    #$psRaw =~ s/\n/<br>/g;
    #print "PS:<br>\n$psRaw<br>";
    my $pods = forcearray( $simp->{'pod'} );
    print "Number of PODS: ". scalar( @$pods ) . "<br>\n";
    print "<table border=1 cellpadding=6 cellspacing=0><tr><th>ID</th><th>Cmd</th><th>Names</th></tr>\n";
    for my $pod ( @$pods ) {
      my $id = $pod->{'id'};
      $id = substr( $id, 0, 4 );
      my $cmd = $pod->{'cmd'};
      my $names = $pod->{'names'};
      my @nameParts = split( "_", $names );
      my $nameText = '';
      if( $nameParts[0] eq 'k8s' ) {
        $nameText .= "<nobr>Container: $nameParts[1]</nobr><br>";
        $nameText .= "<nobr>POD: $nameParts[2]</nobr><br>";
        my $ns = $nameParts[3];
        if( $ns ne 'default' ) {
          $nameText .= "NS: $ns<br>";
        }
      }
      else {
        $nameText = $names;
        $nameText =~ s/_/<br>/g;
      }
      my $labels = $pod->{'labels'};
      my $labelHash = labelHash( $labels );
      my $labelText = '';
      for my $labelKey ( sort keys %$labelHash ) {
        my $labelVal = $labelHash->{ $labelKey };
        $labelText .= "$labelKey = $labelVal<br>\n";
      }
      print "<tr><td>$id</td><td>$cmd</d><td>$nameText</td><td>$labelText</td></tr>";
    }
    print "</table>";
    $ssh->close();
    exit;
  }
  print "Unknown Op: $op<br>";
  exit;
}

sub doDocker {
  my $cmd = shift;
  my %form = @_;
  
  my $format = genFormat( %form );
  my $rawinfo = `docker $cmd --format "<each>$format</each>" --no-trunc 2>&1`;
  if( $rawinfo =~ m/^<each/ ) {
    my ( $ob, $xml ) = XML::Bare->simple( text => $rawinfo );
    my $arr = forcearray $xml->{'each'};
    return $arr;
  }
  die $rawinfo;
}

sub genFormat {
  my %form = @_;
  my $text = '';
  for my $key ( keys %form ) {
    my $name = $form{ $key };
    $text .= "<$key><![CDATA[{{.$name}}]]></$key>";
  }
  return $text;
}

sub labelHash {
  my $labels = shift;
  my %hash;
  my @parts = split( ",", $labels );
  for my $part ( @parts ) {
    if( $part =~ m/(.+)=(.+)/ ) {
      $hash{ $1 } = $2;
    }
  }
  return \%hash;
}

sub readdata {
  my $data = shift;
  my @lines = split( "\n", $data );
  my $curval = '';
  my $curkey = '';
  my %hash;
  for my $line ( @lines ) {
    #print "Line:$line<br>\n";
    if( $line =~ m/^([a-z_]+):$/ ) {
      $hash{ $curkey } = $curval;
      $curval = '';
      $curkey = $1;
    }
    else {
      $curval .= "$line\n";
    }
  }
  return \%hash;
}
  print "<h2>Commands</h2>";
  print "<ul><li><a href='?op=images'>Docker Image List</a></ul>";
  print "<h2>Virsh Domains</h2>";

  my $vmm = Sys::Virt->new(uri => "qemu:///system");

  my @domains = $vmm->list_domains();

  foreach my $dom ( sort { $a->get_name cmp $b->get_name } @domains) {
    my $domName = $dom->get_name;
    print "<b>$domName</b><br>\n";
    my @nics = $dom->get_interface_addresses(Sys::Virt::Domain::INTERFACE_ADDRESSES_SRC_LEASE);
    for my $nic ( @nics ) {
      #print Dumper( $nic );
      my $addrs = $nic->{'addrs'};
      for my $addr ( @$addrs ) {
        my $ip = $addr->{'addr'};
        print "  IP: $ip<br>\n";
      }
      
    }
    
    my $xml = $dom->get_xml_description();
    my ( $ob, $simp ) = XML::Bare->simple( text => $xml );
    #print Dumper( $simp );
    my $fsR = forcearray( $simp->{'domain'}{'devices'}{'filesystem'} );
    #print Dumper( $fs );
    if( @$fsR ) {
      print "Mounts:<br><table border=1 cellpadding=6 cellspacing=0><tr><th>From</th><th>To</th></tr>";
      for my $fs ( @$fsR ) {
        my $type = $fs->{'type'};
        next if( $type ne 'mount' );
        my $target = $fs->{'target'}{'dir'};
        my $source = $fs->{'source'}{'dir'};
        print "<tr><td>$target</td><td>$source</td></tr>\n";
      }
      print "</table>";
    }
    my $disks = forcearray( $simp->{'domain'}{'devices'}{'disk'} );
    print "Disks:<br><table border=1 cellpadding=6 cellspacing=0><tr><th>Bus</th><th>Dev</th><th>File</th></tr>";
    for my $disk ( @$disks ) {
      my $source = $disk->{'source'}{'file'};
      my $target = $disk->{'target'};
      my $dev = $target->{'dev'};
      my $bus = $target->{'bus'};
      my $extra = '';
      if( $source =~ m/cloud_init/ ) {
        $extra = "<a href='?file=$source&op=showinit'>Show Init</a>";
      }
      print "<tr><td>$bus</td><td>$dev</td><td>$source $extra</td></tr>\n";
    }
    print "</table>";
    print "<a href='?op=dockerps&domain=$domName'>Docker PS</a><br>";
    # This is the root filesystem of the node
    #my $fsinfo = $dom->get_fs_info;
    #print Dumper( $fsinfo );
    print "<br><br>";
  }
