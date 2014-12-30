##############################################
# $Id: 31_fronthemDevice.pm 0 2014-10-01 08:00:00Z herrmannj $

package main;

use strict;
use warnings;

use JSON;
use URI::Escape;
use Time::HiRes;
use fhconverter;

use Data::Dumper;

sub
fronthemDevice_Initialize(@)
{

  my ($hash) = @_;
  
  $hash->{DefFn}        = "fronthemDevice_Define";
  $hash->{SetFn}        = "fronthemDevice_Set";
  $hash->{GetFn}        = "fronthemDevice_Get";
  $hash->{NotifyFn}     = "fronthemDevice_Notify";
  $hash->{ShutdownFn}   = "fronthemDevice_Shutdown";
  $hash->{FW_detailFn}  = "fronthemDevice_fwDetail";
  $hash->{AttrList}     = "configFile ".$readingFnAttributes;

  $data{FWEXT}{fronthemDevice}{SCRIPT}  = "fronthemEditor.js";
}

# define name fronthemDevice ip

sub
fronthemDevice_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t][ \t]*", $def);
  my $name = $a[0];
  my $identity = $a[2];

  fronthemDevice_ReadCfg($hash);
  fronthemDevice_Register($hash) if ($init_done);

  readingsBeginUpdate($hash);
  readingsBulkUpdate($hash, "identity", $identity);
  readingsEndUpdate($hash, 0);
  {
    my $converter = 'fronthem';
    no strict 'refs';
    @{$hash->{helper}->{converter}} = grep { defined &{"$converter\::$_"} } keys %{"$converter\::"};
  }
  
  return undef;
}

sub
fronthemDevice_Register(@)
{
  my ($hash) = @_;
  foreach my $key (keys %defs)
  {
    if ($defs{$key}{TYPE} eq 'fronthem')
    {
      $hash->{helper}->{gateway} = $key;
      fronthem_RegisterClient($defs{$key}, $hash->{NAME});
      $hash->{helper}->{init} = 'done';
      last;
    }
  }
  return undef;
}

sub
fronthemDevice_Set(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  if ($cmd eq 'webif-data')
  {
    print Dumper decode_json(uri_unescape($args[0]));
  }
  return undef;
}

sub
fronthemDevice_Get(@)
{
  my ($hash, $name, $cmd, @args) = @_;
  my $cnt = @args;

  if ($cmd eq 'webif-data')
  {
    my $transfer;
    eval 
    {
      $transfer = decode_json(join(' ',@args) || '');
      1;
    } or do {
      my $e = $@;
      log3 ($hash->{NAME}, 1, "Error decoding webif-data $e: ".join(' ',@args));
      return undef;
    };
    print Dumper $transfer;
    if ($transfer->{cmd} eq 'gadList')
    {
      #TODO replace if getConfig is in place to prevent fails if parent is renamed
      my $config = $defs{$hash->{helper}->{gateway}}->{helper}->{config} if ($hash->{helper}->{gateway});
      my $result = {};
      foreach my $key (keys $config)
      {
        my %copy =  %{$config->{$key}}; 
        $result->{$key} = \%copy;
        $result->{$key}->{monitor} = (grep { $_ eq $key } @{$hash->{helper}->{monitor}})?1:0;
        $result->{$key}->{read} = ($hash->{helper}->{config}->{$key}->{read})?1:0;
        $result->{$key}->{write} = ($hash->{helper}->{config}->{$key}->{write})?1:0;
      }
      return encode_json($result);
    }
    elsif ($transfer->{cmd} eq 'gadItem')
    {
      #prepare list and preload val
      #TODO there is a small chance that the item was deleted from other client
      return unless defined($transfer->{item});
      return unless exists($defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}});
      my $result;
      $result->{deviceList} = ();
      $result->{converterList} = ();
      %{$result} = %{$defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}}};
      $result->{device} = '' if (!defined($result->{device}));
      $result->{reading} = '' if (!defined($result->{reading}));
      $result->{converter} = '' if (!defined($result->{converter}));
      $result->{set} = '' if (!defined($result->{set}));
      $result->{read} = ($hash->{helper}->{config}->{$transfer->{item}}->{read} == 1)?'checked':'';
      $result->{write} = ($hash->{helper}->{config}->{$transfer->{item}}->{write} == 1)?'checked':'';
      foreach my $key (keys %defs) 
      {
        push (@{$result->{deviceList}}, $key) unless ($key =~ /FHEMWEB:.*/);
      }
      @{$result->{deviceList}} = sort @{$result->{deviceList}};
      @{$result->{converterList}} = sort @{$hash->{helper}->{converter}};
      #type:mode, js editor support
      $result->{editor} = $result->{type};
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadItemSave')
    {
      my $result;
      #print "webif-data gadItemSave\n";
      #print Dumper $transfer;
      fronthemDevice_ValidateGAD($hash, $transfer);
      $result->{result} = 'ok';
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadModeSelect')
    {
      my $result;
      fronthemDevice_ValidateGAD($hash, $transfer);
      $result->{result} = 'ok';
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadItemDeviceChanged')
    {
      my $result;
      $result->{result} = 'error';
      $result->{readings} = ();
      $result->{sets} = ();
      if ((defined($transfer->{device})) && (exists($defs{$transfer->{device}})) && (exists($defs{$transfer->{device}}->{READINGS})))
      {
        foreach my $key (keys $defs{$transfer->{device}}->{READINGS})
        {
          print "device $key \n";
          push (@{$result->{readings}}, $key);
          @{$result->{readings}} = sort @{$result->{readings}};
        }
        $result->{result} = 'ok';
        my $sl = fhem "set $transfer->{device} ?";
        $sl =~ s/^.*? choose one of //g;
        $sl =~ s/:[^\s\\]+//g;
        @{$result->{sets}} = split(' ', $sl);
        push (@{$result->{sets}}, 'state');
        @{$result->{sets}} = sort @{$result->{sets}};
      }
      return encode_json($result);  
    }
    elsif ($transfer->{cmd} eq 'gadItemDelete')
    {
      my $result;
      $result->{result} = 'ok';
      if (defined($defs{$hash->{helper}->{gateway}}) && exists($defs{$hash->{helper}->{gateway}}))
      {
        delete $defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}};
      }
      return encode_json($result);  
    }
  }
  return undef;
}

sub fronthemDevice_ValidateGAD(@)
{
  my ($hash, $transfer) = @_;

  my $result = '';
  my $gadItem = $transfer->{item};
  if (!defined($defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}}))
  {
    Log3 ($hash, 2, "gadModeSelect with unknown GAD $gadItem");
  }
  my $gadAtGateway = $defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$transfer->{item}};

  #update or set permissions
  $hash->{helper}->{config}->{$gadItem}->{read} = ($transfer->{config}->{read} eq '1')?1:0;
  $hash->{helper}->{config}->{$gadItem}->{write} = ($transfer->{config}->{write} eq '1')?1:0;

  if ($transfer->{editor} eq 'item')
  {
    $gadAtGateway->{type} = 'item';
    #device
    if ((defined($transfer->{config}->{device})) && length($transfer->{config}->{device}))
    {
      $result .= 'device not found. ' if (!exists($defs{$transfer->{config}->{device}}));
      $gadAtGateway->{device} = $transfer->{config}->{device};
    }
    else
    {
      delete ($gadAtGateway->{device});
    }
    #reading
    if ((defined($transfer->{config}->{reading})) && length($transfer->{config}->{reading}))
    {
      $gadAtGateway->{reading} = $transfer->{config}->{reading};
    }
    else
    {
      delete($gadAtGateway->{reading});
    }
    #converter
    if ((defined($transfer->{config}->{converter})) && length($transfer->{config}->{converter}))
    {
      $gadAtGateway->{converter} = $transfer->{config}->{converter};
    }
    else
    {
      delete($gadAtGateway->{converter});
    }
    #set
    if ((defined($transfer->{config}->{set})) && length($transfer->{config}->{set}))
    {
      $gadAtGateway->{set} = $transfer->{config}->{set};
    }
    else
    {
      delete($gadAtGateway->{set});
    }
  }
  #TODO find something more clever 
  fronthemDevice_WriteCfg($hash);
  fronthem_WriteCfg($defs{$hash->{helper}->{gateway}});
}

sub 
fronthemDevice_Notify($$)
{
  my ($hash, $ntfyDev) = @_;
  my $ntfyDevName = $ntfyDev->{NAME};

  #find parent if initialization done
  fronthemDevice_Register($hash) if (!$hash->{helper}->{init} && ($ntfyDevName eq 'global') && grep(m/^INITIALIZED$/, @{$ntfyDev->{CHANGED}}));
  return undef if(AttrVal($hash->{NAME}, "disable", 0) == 1);

  my $result;

  #TODO exit here if gateway is absend

  #of interest, device is in global (context fronthem parent device) list of known device->reading->gad ?
  if (defined($hash->{helper}->{gateway}) && exists($defs{$hash->{helper}->{gateway}}->{helper}->{listen}->{$ntfyDevName}))
  {
    my $max = int(@{$ntfyDev->{CHANGED}});
    my $gateway = $hash->{helper}->{gateway};
    my $listenDevice = $defs{$gateway}->{helper}->{listen}->{$ntfyDevName};

    for (my $i = 0; $i < $max; $i++) {
      my $s = $ntfyDev->{CHANGED}[$i];
      $s = "state: $s" if (($ntfyDevName ne 'global') && ($s !~ m/.*:.*/));
      $s =~ s/://;
      my @reading = split(' ', $s);
      if (defined($listenDevice->{$reading[0]}))
      {
        #global list of all gad using it
        foreach my $gad (keys $listenDevice->{$reading[0]})
        {
          #test local access rules
          #est it against local monitor list
          grep
          {
            if ($gad eq $_)
            {
              #test whats to do with, converter type
              my $gadCfg = $defs{$gateway}->{helper}->{config}->{$gad};
              if ($gadCfg->{type} eq 'item')
              {
                my ($converter, $p) = split(/\s+/, $gadCfg->{converter}, 2);
                #print "conv $converter\n";
                my $param;
                $param->{cmd} = 'send';
                $param->{gad} = $gad;
                $param->{device} = $ntfyDevName;
                $param->{reading} = $reading[0];
                $param->{event} = $reading[1];
                @{$param->{events}} = @reading;
                @{$param->{args}} = split(/\s*,\s*/, $p || '');
                fronthemDevice_DoConverter($hash, $converter, $param);
              }
            }
          } @{$hash->{helper}->{monitor}};
        }
      }
    }
  }
  return undef;
}

#
sub
fronthemDevice_DoConverter(@)
{
  my ($hash, $converter, $param) = @_;
  return undef unless length($converter);
  my $result;
  my $convStr = "\$result = fronthem::$converter(\$param);";

  #check local permissions
  my $gad = $param->{gad};
  my $cmd = $param->{cmd};
  #cmd == get||send: device is allowed to read the via that gad ?
  if ($cmd =~/get|send/)
  {
    #return undef $hash->{helper}->{config}->{$gad}->{read};
    Log3 ($hash, 3, "$hash->{NAME} no read permission for $gad") unless $hash->{helper}->{config}->{$gad}->{read};
    #TODO check pin assignment
    #if (defined($hash->{helper}->{config}->{$gad}->{NAME_OF_GAD_THAT_IS_USED_TO_TEST}))
    #{
    #  return undef if pad_pin_special_cache_entry != extracted pin from key
    #}
  }
  #cmd == rcv: device is allowed to execute (write) via that gad ?
  if ($cmd eq 'rcv')
  {
    #return undef unless $hash->{helper}->{config}->{$gad}->{write};
    Log3 ($hash, 3, "$hash->{NAME} no write permission for $gad") unless $hash->{helper}->{config}->{$gad}->{write};
    #TODO check pin assignment
    #if (defined($hash->{helper}->{config}->{$gad}->{NAME_OF_GAD_THAT_IS_USED_TO_TEST}))
    #{
    #  return undef if pad_pin_special_cache_entry != extracted pin from key
    #}
  }
  eval $convStr and do 
  {
    #if there is a return value from converter, the converter may have chosen thats nothing to do, done by itslelf or a error is risen
    return undef if ($result eq 'done');
    return Log3 ($hash, 1, "$hash->{NAME}: $result");
  };
  print "res $@ \n";
  if ($cmd =~/get|send/)
  {
    my $msg;
    $msg->{receiver} = $hash->{NAME};
    $msg->{message}->{cmd} = 'item';
    @{$msg->{message}->{items}} = @{$param->{gads}}?@{$param->{gads}}:($param->{gad}, $param->{gadval});
    fronthemDevice_toDriver($hash, $msg);
    return undef;
  }
  elsif ($cmd = 'rcv')
  {
    my $device = $param->{device};
    my $set = fronthemDevice_ConfigVal($hash, $gad, 'set');
    $set =~ s/^state// if ($param->{reading} eq 'state');
    if ($set !~/.*\$.*/)
    {
      fhem "set $device $set $param->{result}";
      return undef;
    }
    else
    {
      #TODO eval with vars
    }
  }
}

sub
fronthemDevice_Shutdown(@)
{
  return undef;
}

sub
fronthemDevice_fwDetail(@)
{
  my ($FW_wname, $d, $FW_room) = @_;
  my $result = '';

  $result = "<div>\n";
  $result .= "<table class=\"block wide \">\n";
  $result .= "<tr>\n";
  $result .= "<td>\n";
  $result .= "<div id=\"gadlist\" style=\"max-height: 200px; overflow-y: scroll;\"></div>\n";
  $result .= "</td>\n";
  $result .= "</tr>\n";
  $result .= "</table>\n";
  $result .= "<script type='text/javascript'>\n";
  $result .= "sveReadGADList('$d');\n";
  $result .= "</script>\n";
  $result .= "</div>\n";
  $result .= "<div id=\"gadeditcontainer\" style=\"display: none;\">\n";
  $result .= "<br>";
  $result .= "GAD Edit\n";
  $result .= "<table class=\"block wide \">\n";
  $result .= "<tr>\n";
  $result .= "<td>\n";
  $result .= "<div id=\"gadeditor\">Editor<br>1</div>\n";
  $result .= "</td>\n";
  $result .= "</tr>\n";
  $result .= "</table>\n";
  $result .= "</div>\n";
  
  return $result;
}

sub
fronthemDevice_ReadCfg(@)
{
  my ($hash) = @_;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "fhclient.$hash->{NAME}.cfg");
  $cfgFile = "./www/fronthem/clients/$hash->{NAME}/$cfgFile";

  my $json_text = '';
  my $json_fh;
  open($json_fh, "<:encoding(UTF-8)", $cfgFile) and do
  {
    #Log3 ($hash, 1, "$hash->{NAME}: Error loading cfg file $!");
    local $/;
    $json_text = <$json_fh>;
    close $json_fh;
  };

  my $data;
  eval 
  {
    my $json = JSON->new->utf8;
    $data = $json->decode($json_text);
    1;
  } or do {
    Log3 ($hash, 1, "$hash->{NAME}: Error loading cfg file $@");
    return undef;
  };
  $hash->{helper}->{config} = $data->{config};
  return undef;
}

sub
fronthemDevice_WriteCfg(@)
{
  my ($hash) = @_;
  my $cfgContent;
  my $cfgFile = AttrVal($hash->{NAME}, 'configFile', "fhclient.$hash->{NAME}.cfg");

  $cfgContent->{version} = '1.0';
  $cfgContent->{modul} = 'fronthem-client';
  
  foreach my $key (keys %{ $hash->{helper}->{config} })
  {
    $cfgContent->{config}->{$key}->{read} = $hash->{helper}->{config}->{$key}->{read}?1:0;
    $cfgContent->{config}->{$key}->{write} = $hash->{helper}->{config}->{$key}->{write}?1:0;
  }

  mkdir('./www/fronthem',0777) unless (-d './www/fronthem');
  mkdir('./www/fronthem/clients',0777) unless (-d './www/fronthem/clients');
  mkdir("./www/fronthem/clients/$hash->{NAME}",0777) unless (-d "./www/fronthem/clients/$hash->{NAME}");

  $cfgFile = "./www/fronthem/clients/$hash->{NAME}/$cfgFile";

  my $cfgOut = JSON->new->utf8;
  open (my $cfgHandle, ">:encoding(UTF-8)", $cfgFile);
  print $cfgHandle $cfgOut->pretty->encode($cfgContent);
  close $cfgHandle;;

  return undef;
}

sub
fronthemDevice_ConfigVal(@)
{
  my ($hash, $gad, $subKey) = @_;
  return undef unless (defined($hash->{helper}->{gateway}) && length($hash->{helper}->{gateway}) && exists($defs{$hash->{helper}->{gateway}}));
  return undef unless (exists($defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$gad}));
  return $defs{$hash->{helper}->{gateway}}->{helper}->{config}->{$gad}->{$subKey};
}

# communicating with sv main instance
sub
fronthemDevice_fromDriver(@)
{
  my ($hash, $msg) = @_;
  if (($msg->{message}->{cmd} ne 'disconnect') && (ReadingsVal($hash->{NAME}, 'state', '') ne 'connected'))
  {
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', 'connected');
    readingsEndUpdate($hash, 1);
    #return undef;
  }
  if ($msg->{message}->{cmd} eq 'disconnect')
  {
    $hash->{helper}->{monitor} = [];
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'state', 'disconnected');
    readingsEndUpdate($hash, 1);
    return undef;
  }
  if ($msg->{message}->{cmd} eq 'proto')
  {
    #TODO check if protokoll version match
    readingsBeginUpdate($hash);
    readingsBulkUpdate($hash, 'protokoll', $msg->{message}->{ver});
    readingsEndUpdate($hash, 1);
    return undef;
  }
  if ($msg->{message}->{cmd} eq 'monitor')
  {
    $hash->{helper}->{monitor} = $msg->{message}->{items};
    foreach my $gad (@{$hash->{helper}->{monitor}})
    {
      #clear cache count
      $hash->{helper}->{cache}->{$gad}->{count} = 0;
      #call if a converter is set
      print "monitor $gad \n";
      if (fronthemDevice_ConfigVal($hash, $gad, 'converter'))
      {
        my $param;
        $param->{cmd} = 'get';
        $param->{gad} = $gad;
        $param->{device} = fronthemDevice_ConfigVal($hash, $gad, 'device');
        $param->{reading} = fronthemDevice_ConfigVal($hash, $gad, 'reading');
        my ($converter, $p) = split(/\s+/, fronthemDevice_ConfigVal($hash, $gad, 'converter'), 2);
        @{$param->{args}} = split(/\s*,\s*/, $p || '');
        fronthemDevice_DoConverter($hash, $converter, $param);
      }
    }
    return undef;
  }
  if ($msg->{message}->{cmd} eq 'item')
  {
    $hash->{helper}->{cache}->{$msg->{message}->{id}}->{val} = $msg->{message}->{val};
    $hash->{helper}->{cache}->{$msg->{message}->{id}}->{time} = gettimeofday();
    $hash->{helper}->{cache}->{$msg->{message}->{id}}->{count} += 1;

    my $gad = $msg->{message}->{id};
    my $gadval = $msg->{message}->{val};

    if (fronthemDevice_ConfigVal($hash, $gad, 'converter'))
    {
      my $param;
      $param->{cmd} = 'rcv';
      $param->{gad} = $gad;
      $param->{gadval} = $gadval;
      $param->{device} = fronthemDevice_ConfigVal($hash, $gad, 'device');
      $param->{reading} = fronthemDevice_ConfigVal($hash, $gad, 'reading');
      $param->{cache} = $hash->{helper}->{cache};
      my ($converter, $p) = split(/\s+/, fronthemDevice_ConfigVal($hash, $gad, 'converter'), 2);
      @{$param->{args}} = split(/\s*,\s*/, $p || '');
      #print "in item loop: $converter \n";
      #print Dumper $param;
      fronthemDevice_DoConverter($hash, $converter, $param);
    }
    return undef;
  }
  #print Dumper $msg;
  return undef;
}

sub
fronthemDevice_toDriver(@)
{
  my ($hash, $msg) = @_;
  fronthem_FromDevice($defs{$hash->{helper}->{gateway}}, $hash->{NAME}, $msg) if ((defined($hash->{helper}->{gateway})) && length($hash->{helper}->{gateway}));
  return undef;
}


1;
