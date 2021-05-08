##############################################
# $Id: 32_Iluminize.pm 23748 2021-05-06 16:30:00Z johannes bosecker $
#
# maintainer: Johannes Bosecker, j.bosecker.dev@icloud.com
#

package main;

use strict;
use warnings;

sub Iluminize_Initialize {
    my ($hash) = @_;

    $hash->{DefFn}        = "Iluminize::Define";
    $hash->{UndefFn}      = "Iluminize::Undef";
    $hash->{SetFn}        = "Iluminize::Set";
    $hash->{GetFn}        = "Iluminize::Get";
    $hash->{AttrList}     = "disable:0,1 senderId rgbMax whiteMax";

    return undef;
}

package Iluminize;

use IO::Socket;
use GPUtils qw(:all);

BEGIN {
    GP_Import(qw(
        readingsSingleUpdate
        readingsBulkUpdate
        readingsBeginUpdate
        readingsEndUpdate
        AttrVal
        ReadingsVal
        Log3
    ))
};

# === FHEM callback functions ===

sub Define {
    my ($hash, $def) = @_;
    my @a = split("[ \t][ \t]*", $def);
    return "wrong syntax: define <name> Iluminize <LEDTYPE> <IP>" if(@a != 4);
    
    my $name = $a[0];
    return "only <LEDTYPE> 'WHITE' and 'RGBW' are supported." if(($a[2] ne "WHITE") and ($a[2] ne "RGBW"));
    
    $hash->{LEDTYPE} = $a[2];
    
    if ($a[3] =~ m/(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}):*(\d+)*/g) {
        $hash->{STATE} = 'off';
        $hash->{IP} = $1;
        $hash->{PORT} = $2?$2:8899;
    }
    else {
        return "Please provide a valid IPv4 address \n\ni.e. \n192.168.1.28";
    }
    
    if (!defined($hash->{helper}->{SOCKET})) {
        my $sock = IO::Socket::INET-> new (
            PeerPort => $hash->{PORT},
            PeerAddr => $hash->{IP},
            Timeout => 1,
            Blocking => 0,
            Proto => 'tcp') or Log3 ($hash, 3, "define $hash->{NAME}: can't reach ($@)");
        my $select = IO::Select->new($sock);
        $hash->{helper}->{SOCKET} = $sock;
        $hash->{helper}->{SELECT} = $select;
    }
    
    readingsBeginUpdate($hash);

    if ($hash->{LEDTYPE} eq 'WHITE') {
        initializeReadingsValueBulk($hash, "w", "0F");
        initializeReadingsValueBulk($hash, "whiteBrightness", "0");
        initializeReadingsValueBulk($hash, "whiteState", "off");
    }
    elsif ($hash->{LEDTYPE} eq 'RGBW') {
        initializeReadingsValueBulk($hash, "rgb", "0F0F0F");
        initializeReadingsValueBulk($hash, "w", "0F");
        initializeReadingsValueBulk($hash, "rgbBrightness", "0");
        initializeReadingsValueBulk($hash, "whiteBrightness", "0");
        initializeReadingsValueBulk($hash, "rgbState", "off");
        initializeReadingsValueBulk($hash, "whiteState", "off");
        initializeReadingsValueBulk($hash, "rgbHue", "0");
        initializeReadingsValueBulk($hash, "rgbSaturation", "0");
    }
    
    initializeReadingsValueBulk($hash, "state", "off");
    initializeReadingsValueBulk($hash, "mode", "W");
    readingsEndUpdate($hash, 1);
    
    return undef;
}

sub Undef {
    return undef;
}

sub Set {
    my ($device, $name, $cmd, @args) = @_;

    #command checking
    if ($device->{LEDTYPE} eq 'RGBW')
    {
        return "Unknown argument $cmd, choose one of rgb:colorpicker,RGB w whiteBrightness:slider,0,1,100 rgbBrightness:slider,0,1,100 on:noArg rgbOn:noArg whiteOn:noArg off:noArg rgbOff:noArg whiteOff:noArg rgbHue:slider,0,1,360 rgbSaturation:slider,0,1,100 brightness:slider,0,1,100" if
            (
                ($cmd ne 'rgb') and
                ($cmd ne 'w') and
                ($cmd ne 'whiteBrightness') and
                ($cmd ne 'rgbBrightness') and
                ($cmd ne 'on') and
                ($cmd ne 'rgbOn') and
                ($cmd ne 'whiteOn') and
                ($cmd ne 'off') and
                ($cmd ne 'rgbOff') and
                ($cmd ne 'whiteOff') and
                ($cmd ne 'rgbHue') and
                ($cmd ne 'rgbSaturation') and
                ($cmd ne 'rgbBrightness') and
                ($cmd ne 'brightness')
            );
    }
    else
    {
        return "Unknown argument $cmd, choose one of w whiteBrightness:slider,0,1,100 on:noArg whiteOn:noArg off:noArg whiteOff:noArg brightness:slider,0,1,100" if
            (
                ($cmd ne 'w') and
                ($cmd ne 'whiteBrightness') and
                ($cmd ne 'on') and
                ($cmd ne 'whiteOn') and
                ($cmd ne 'off') and
                ($cmd ne 'whiteOff') and
                ($cmd ne 'brightness')
            );
    }
    
    #value checking
    if ($cmd eq 'rgb') {
        return "one value must be specified for rgb command" if (@args != 1);
        return "only hex values like FFFFFF allowed for rgb command" if ($args[0] !~ m/^([0-9A-Fa-f]{6})$/g );
    }
    elsif ($cmd eq 'w') {
        return "one value must be specified for w command" if (@args != 1);
        return "only hex values like FF allowed for w command" if ($args[0] !~ m/^([0-9A-Fa-f]{2})$/g );
    }
    elsif (($cmd eq 'brightness')) {
        return "one value must be specified for a brightness command" if (@args != 1);
        return "only values 0 to 100 allowed for brightness command" if ($args[0] !~ m/^([0-9]|[1-9][0-9]|100)$/g );
    }
    elsif (($cmd eq 'whiteBrightness')) {
        return "one value must be specified for a whiteBrightness command" if (@args != 1);
        return "only values 0 to 100 allowed for whiteBrightness command" if ($args[0] !~ m/^([0-9]|[1-9][0-9]|100)$/g );
    }
    elsif (($cmd eq 'rgbBrightness')) {
        return "one value must be specified for a rgbBrightness command" if (@args != 1);
        return "only values 0 to 100 allowed for rgbBrightness command" if ($args[0] !~ m/^([0-9]|[1-9][0-9]|100)$/g );
    }
    elsif (($cmd eq 'rgbHue')) {
        return "one value must be specified for a rgbHue command" if (@args != 1);
        return "only values 0 to 360 allowed for rgbHue command" if ($args[0] < 0 || $args[0] > 360);
    }
    elsif (($cmd eq 'rgbSaturation')) {
        return "one value must be specified for a rgbSaturation command" if (@args != 1);
        return "only values 0 to 100 allowed for rgbSaturation command" if ($args[0] < 0 || $args[0] > 100);
    }
    else {
        return "no value must be specified for on, off, animationStop commands" if (@args != 0);
    }

    #sender id checking
    my $senderId = AttrVal($device->{NAME}, "senderId", undef);
    return "you have to specify the attribute senderId" if (!defined($senderId));
    return "wrong senderId format (should be AABBCC)" if ($senderId !~ m/^([0-9A-Fa-f]{6})$/g );

    if ($cmd eq 'rgb') {
        my $r = hex substr($args[0], 0, 2);
        my $g = hex substr($args[0], 2, 2);
        my $b = hex substr($args[0], 4, 2);
        
        setRgb($device, $r, $g, $b);
    }
    elsif ($cmd eq 'w') {
        my $w = hex $args[0];
        
        setWhite($device, $w);
    }
    elsif ($cmd eq 'rgbHue') {
        my $value = $args[0];
        
        setRgbHue($device, $value);
    }
    elsif ($cmd eq 'rgbSaturation') {
        my $value = $args[0];
        
        setRgbSaturation($device, $value);
    }
    elsif ($cmd eq 'rgbBrightness') {
        my $value = $args[0];
        
        setRgbBrightness($device, $value);
    }
    elsif ($cmd eq 'whiteBrightness') {
        my $value = $args[0];
        
        setWhiteBrightness($device, $value);
    }
    elsif ($cmd eq 'brightness') {
        my $value = $args[0];
        
        setBrightness($device, $value);
    }
    elsif ($cmd eq 'on') {
        setOn($device);
    }
    elsif ($cmd eq 'rgbOn') {
        setRgbOn($device);
    }
    elsif ($cmd eq 'whiteOn') {
        setWhiteOn($device);
    }
    elsif ($cmd eq 'off') {
        setOff($device);
    }
    elsif ($cmd eq 'rgbOff') {
        setRgbOff($device);
    }
    elsif ($cmd eq 'whiteOff') {
        setWhiteOff($device);
    }
}

sub Get {

}

# === Set functions ===

sub setRgb {
    my ($device, $r, $g, $b) = @_;
    
    my ($hue, $saturation, $brightness) = Color::rgb2hsb($r, $g, $b);
    
    readingsBeginUpdate($device);
    readingsBulkUpdate($device, "rgbHue", convertHueToDegree($hue));
    readingsBulkUpdate($device, "rgbSaturation", convertSaturationToPercent($saturation));
    readingsEndUpdate($device, 1);
    
    setRgbBrightness($device, convertBrightnessToPercent($brightness));
}

sub setWhite {
    my ($device, $w) = @_;
    
    setWhiteBrightness($device, convertBrightnessToPercent($w));
}

sub setOn {
    my ($device) = @_;
    
    my $mode = getMode($device);
    
    if ($mode eq "RGB") {
        setRgbOn($device);
    }
    elsif ($mode eq "W") {
        setWhiteOn($device);
    }
    else {
        setRgbOn($device);
        setWhiteOn($device);
    }
}

sub setOff {
    my ($device) = @_;
    
    my $mode = getMode($device);
    
    if ($mode eq "RGB") {
        setRgbOff($device);
    }
    elsif ($mode eq "W") {
        setWhiteOff($device);
    }
    else {
        setRgbOff($device);
        setWhiteOff($device);
    }
}

sub setRgbOn {
    my ($device) = @_;
    
    my $brightness = getRgbLastBrightness($device);
    setRgbBrightness($device, $brightness);
}

sub setRgbOff {
    my ($device) = @_;
    
    setRgbBrightness($device, 0);
}

sub setWhiteOn {
    my ($device) = @_;
    
    my $brightness = getWhiteLastBrightness($device);
    setWhiteBrightness($device, $brightness);
}

sub setWhiteOff {
    my ($device) = @_;
    
    setWhiteBrightness($device, 0);
}

sub setRgbBrightness {
    my ($device, $value) = @_;
    
    my ($hue, $saturation, $brightness) = getRgbHueSaturationBrightness($device);
    $brightness = $value;
    my ($r, $g, $b) = Color::hsb2rgb(convertDegreeToHue($hue), convertPercentToSaturation($saturation), convertPercentToBrightness($brightness));
    
    my ($rMax, $gMax, $bMax) = getRgbMax($device);
    transmitRgb($device, $r / 255 * $rMax, $g / 255 * $gMax, $b / 255 * $bMax);
    
    readingsBeginUpdate($device);
    readingsBulkUpdate($device, "rgbBrightness", $brightness);
    
    if ($brightness > 0) {
        readingsBulkUpdate($device, "rgbLastBrightness", $brightness);
    }
    
    readingsEndUpdate($device, 1);
    
    updateRgbState($device);
    updateState($device);
}

sub setWhiteBrightness {
    my ($device, $value) = @_;
    
    my $brightness = $value;
    
    transmitWhite($device, convertPercentToBrightness($brightness));
    
    readingsBeginUpdate($device);
    
    readingsBulkUpdate($device, "whiteBrightness", $brightness);
    
    if ($brightness > 0) {
        readingsBulkUpdate($device, "whiteLastBrightness", $brightness);
    }
    
    readingsEndUpdate($device, 1);
    
    updateWhiteState($device);
    updateState($device);
}

sub setBrightness {
    my ($device, $value) = @_;
    
    my $mode = getMode($device);
    
    if ($mode eq "RGB") {
        setRgbBrightness($device, $value);
    }
    elsif ($mode eq "W") {
        setWhiteBrightness($device, $value);
    }
    else {
        setRgbBrightness($device, $value);
        setWhiteBrightness($device, $value);
    }
}

sub setRgbHue {
    my ($device, $value) = @_;
    
    readingsBeginUpdate($device);
    readingsBulkUpdate($device, "rgbHue", $value);
    readingsEndUpdate($device, 1);
    
    my $brightness = getRgbLastBrightness($device);
    
    setRgbBrightness($device, $brightness);
}

sub setRgbSaturation {
    my ($device, $value) = @_;
    
    readingsBeginUpdate($device);
    readingsBulkUpdate($device, "rgbSaturation", $value);
    readingsEndUpdate($device, 1);
    
    my $brightness = getRgbLastBrightness($device);
    
    setRgbBrightness($device, $brightness);
}

# === Get functions ===

sub getRgbMax {
    my ($device) = @_;
    
    my $rgbMaxString = AttrVal($device->{NAME}, "rgbMax", "FFFFFF");
    my $rMax = hex substr($rgbMaxString, 0, 2);
    my $gMax = hex substr($rgbMaxString, 2, 2);
    my $bMax = hex substr($rgbMaxString, 4, 2);
    
    return ($rMax, $gMax, $bMax);
}

sub getWhiteMax {
    my ($device) = @_;
    
    my $wMaxString = AttrVal($device->{NAME}, "whiteMax", "FF");
    my $wMax = hex substr($wMaxString, 0, 2);
    
    return $wMax;
}

sub getRgbHueSaturationBrightness {
    my ($device) = @_;
    
    my $hue = ReadingsVal($device->{NAME}, "rgbHue", undef);
    my $saturation = ReadingsVal($device->{NAME}, "rgbSaturation", undef);
    my $brightness = ReadingsVal($device->{NAME}, "rgbBrightness", undef);
    
    return ($hue, $saturation, $brightness);
}

sub getRgbLastBrightness {
    my ($device) = @_;
    
    my $lastBrightness = ReadingsVal($device->{NAME}, "rgbLastBrightness", undef);
    
    return $lastBrightness;
}

sub getWhiteBrightness {
    my ($device) = @_;
    
    my $brightness = ReadingsVal($device->{NAME}, "whiteBrightness", undef);
    
    return $brightness;
}

sub getWhiteLastBrightness {
    my ($device) = @_;
    
    my $lastBrightness = ReadingsVal($device->{NAME}, "whiteLastBrightness", undef);
    
    return $lastBrightness;
}

sub getRgbState {
    my ($device) = @_;
    
    my $rgbState = ReadingsVal($device->{NAME}, "rgbState", undef);
    return $rgbState;
}

sub getWhiteState {
    my ($device) = @_;
    
    my $whiteState = ReadingsVal($device->{NAME}, "whiteState", undef);
    return $whiteState;
}

sub getState {
    my ($device) = @_;
    
    my $state = ReadingsVal($device->{NAME}, "state", undef);
    return $state;
}

sub getSenderId {
    my ($device) = @_;
    
    my $senderId = AttrVal($device->{NAME}, "senderId", undef);
    my $d1 = hex substr($senderId, 0, 2);
    my $d2 = hex substr($senderId, 2, 2);
    my $d3 = hex substr($senderId, 4, 2);
    
    return ($d1, $d2, $d3);
}

sub getMode {
    my ($device) = @_;
    my $mode = ReadingsVal($device->{NAME}, "mode", undef);
    return $mode;
}

# === Basic transmitting functions ===

sub transmitRgb {
    my ($device, $r, $g, $b) = @_;
    
    my ($d1, $d2, $d3) = getSenderId($device);
    
    my $command = checksum($device, pack('C*', 0x55, $d1, $d2, $d3, 0xF2, 0x01, $r, $g, $b, 0x00, 0xAA, 0xAA));
    
    transmit($device, $command);
}

sub transmitWhite {
    my ($device, $w) = @_;
    
    my ($d1, $d2, $d3) = getSenderId($device);
    
    my $command = checksum($device, pack('C*', 0x55, $d1, $d2, $d3, 0x00, 0x01, 0x08, 0x4B, $w, 0x00, 0xAA, 0xAA));
    transmit($device, $command);
}

sub transmit {
    my ($device, $cmd) = @_;
    
    # double the command, so the chance of successful transmission is increased
    $cmd = $cmd . $cmd;
    
    my $debug = unpack("H*", $cmd);
    # TCP
    if (!$device->{helper}->{SOCKET} || ($device->{helper}->{SELECT}->can_read(0.0001) && !$device->{helper}->{SOCKET}->recv(my $data, 512))) {
        Log3 ($device, 4, "$device->{NAME} send $debug, connection refused: trying to reconnect");

        $device->{helper}->{SOCKET}->close() if $device->{helper}->{SOCKET};

        $device->{helper}->{SOCKET} = IO::Socket::INET-> new (
            PeerPort => $device->{PORT},
            PeerAddr => $device->{IP},
            Timeout => 1,
            Blocking => 0,
            Proto => 'tcp') or Log3 ($device, 3, "$device->{NAME} send ERROR $debug (reconnect giving up)");
        $device->{helper}->{SELECT} = IO::Select->new($device->{helper}->{SOCKET}) if $device->{helper}->{SOCKET};
    }
    
    $device->{helper}->{SOCKET}->send($cmd) if $device->{helper}->{SOCKET};

    return undef;
}

sub checksum {
    my ($ledDevice, $msg) = @_;

    my @byteStream = unpack('C*', $msg);
    my $l = @byteStream;
    my $c = 0;

    for (my $i=4; $i<($l-3); $i++) {
        $c += $byteStream[$i];
    }
    
    $c %= 0x100;
    $byteStream[$l -3]  = $c;
    $msg = pack('C*', @byteStream);
    return $msg;
}

# === Readings initialization functions ===

sub initializeReadingsValueBulk {
    my ($device, $reading, $value) = @_;

    if (!defined(ReadingsVal($device->{NAME}, $reading, undef))) {
        readingsBulkUpdate($device, $reading, $value);
    }
}

# === Update state functions ===

sub updateRgbState {
    my ($device) = @_;
    
    my ($hue, $saturation, $brightness) = getRgbHueSaturationBrightness($device);

    my $rgbState = "off";
    
    if ($brightness > 0) {
        $rgbState = "on";
    }
    
    readingsBeginUpdate($device);
    
    if (getRgbState($device) ne $rgbState) {
        readingsBulkUpdate($device, "rgbState", $rgbState);
    }
    
    readingsEndUpdate($device, 1);
}

sub updateWhiteState {
    my ($device) = @_;
    
    my $brightness = getWhiteBrightness($device);
    
    my $whiteState = "off";
    
    if ($brightness > 0) {
        $whiteState = "on";
    }
    
    readingsBeginUpdate($device);

    if (getWhiteState($device) ne $whiteState) {
        readingsBulkUpdate($device, "whiteState", $whiteState);
    }
    
    readingsEndUpdate($device, 1);
}

sub updateState {
    my ($device) = @_;
    
    my ($rgbHue, $rgbSaturation, $rgbBrightness) = getRgbHueSaturationBrightness($device);
    my $whiteBrightness = getWhiteBrightness($device);
    
    my $state = "off";
    my $mode = "";
    
    if ($rgbBrightness > 0) {
        $state = "on";
        $mode = "RGB";
    }
    
    if ($whiteBrightness > 0) {
        $state = "on";
        $mode = $mode . "W";
    }
    
    readingsBeginUpdate($device);
    
    if (getState($device) ne $state) {
        readingsBulkUpdate($device, "state", $state);
    }
    
    if (length($mode) > 0) {
        readingsBulkUpdate($device, "mode", $mode);
    }
    
    readingsEndUpdate($device, 1);
}

# === Helper functions ===

sub buildRgbString {
    my ($r, $g, $b) = @_;
    return sprintf("%02X", $r) . sprintf("%02X", $g) . sprintf("%02X", $b);
}

sub buildWhiteString {
    my ($w) = @_;
    return sprintf("%02X", $w);
}

sub convertHueToDegree {
    my ($value) = @_;
    return $value / 65535 * 360;
}

sub convertDegreeToHue {
    my ($value) = @_;
    return $value / 360 * 65535;
}

sub convertSaturationToPercent {
    my ($value) = @_;
    return $value / 255 * 100;
}

sub convertPercentToSaturation {
    my ($value) = @_;
    return $value / 100 * 255;
}

sub convertBrightnessToPercent {
    my ($value) = @_;
    return $value / 255 * 100;
}

sub convertPercentToBrightness {
    my ($value) = @_;
    return $value / 100 * 255;
}

1;

=pod

=item summary controls the Iluminize WiFi LED Controller through a TCP connection

=begin html

<a name="Iluminize"></a>
<h3>Iluminize</h3>
<ul>
    <i>Iluminize</i> provides communication with Iluminze Light Controller devices via TCP. The protocol is proprietary, so a lot of information is missing.
    <br><br>
    <a name="Iluminize_Define"></a>
    <b>Define</b>
    <ul>
        <code>define &lt;name&gt; Iluminze &lt;type&gt; &lt;host&gt;</code>
        <br><br>
        Example:<br/>
        <code>
          # define a 'RGBW' device using the ip address 192.168.1.10<br/>
          define LedLightStrip Iluminze RGBW 192.168.1.10 <br/><br/>
          # define a 'WHITE' device using the ip address 192.168.1.10<br/>
          define LedLightStrip Iluminze WHITE 192.168.1.10 <br/><br/>
        </code>
        <br><br>
        <code>&lt;name&gt;</code> can be any string describing the devices name within FHEM<br/>
        <code>&lt;type&gt;</code> can be one of the following device-type: <code>RGBW</code>, <code>WHITE</code><br/>
        <code>&lt;host&gt;</code> can be provided with the following format: <code>192.168.1.10</code>, <code>myledstrip.local</code>
    </ul>
    <br>
    <a name="Iluminize_Attr"></a>
    <b>Attr</b><br>
    <ul>
      <li>
        <p><code>set &lt;name&gt; <b>senderId</b> AABBCC</code></p>
        <p>This ID is needed for the communication of the device. You can grab it by sniffing the communication from your smartphone to the WiFi controller.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbMax</b> RRGGBB</code></p>
        <p>The maximum value for the RGB LEDs, which is sent to the controller. Default is FFFFFF.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>whiteMax</b> WW</code></p>
        <p>The maximum value for the white LEDs, which is sent to the controller. Default is FF.</p>
      </li>
    </ul>
    <br>
    <a name="Iluminize_Set"></a>
    <b>Set</b><br>
    <ul>
      <li>
        <p><code>set &lt;name&gt; <b>on</b></code></p>
        <p>Turns the device on. Based on the reading <b>mode</b> it will restore the values, which are stored in <b>rgbBrightness</b>, <b>rgbSaturation</b>, <b>rgbHue</b> and <b>whiteBrightness</b>.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbOn</b></code></p>
        <p>Turns the RGB LEDs on. It will restore the last values (hue, saturation, brightness).</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>whiteOn</b></code></p>
        <p>Turns the white LEDs on. It will restore the last value (brightness).</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>off</b></code></p>
        <p>Turns the device off.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbOff</b></code></p>
        <p>Turns the RGB LEDs off.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>whiteOff</b></code></p>
        <p>Turns the white LEDs off.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgb</b> RRGGBB</code></p>
        <p>Calculates the brightness, saturation and hue and sets the values to the RGB LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>w</b> WW</code></p>
        <p>Calculates the brightness and sets the values to the white LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbBrightness</b> value</code></p>
        <p>Sets the given brightness to the RGB LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbSaturation</b> value</code></p>
        <p>Sets the given saturation to the RGB LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>rgbHue</b> value</code></p>
        <p>Sets the given hue to the RGB LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>whiteBrightness</b> value</code></p>
        <p>Sets the given brightness to the white LEDs.</p>
      </li>
      <li>
        <p><code>set &lt;name&gt; <b>brightness</b> value</code></p>
        <p>Sets the brightness based on the reading <b>mode</b> to either RGB LEDs, white LEDs or both.</p>
      </li>
    </ul>
    <br>
    <a name="Iluminize_Readings"></a>
    <b>Readings</b><br>
    <ul>
      Iluminize devices generally have the following readings:
      <ul>
            <li><b>state</b> - the state of the device (on | off)</li>
            <li><b>mode</b> - the current mode of the device (RGB | W | RGBW)</li>
            <li><b>brightness</b> - the current brightness based on <b>mode</b> in percent (0..100)</li>
      </ul><br/>
      Iluminize devices with the type "WHITE" have the following readings additionally:
      <ul>
            <li><b>w</b> - the hex value of the white LEDs (00..FF)</li>
            <li><b>whiteBrightness</b> - the brightness of the white LEDs in percent (0..100)</li>
            <li><b>whiteState</b> - the state of the white LEDs (on | off)</li>
      </ul><br/>
      Iluminize devices with the type "RGBW" additionally have the following readings additionally to type "WHITE":
      <ul>
            <li><b>rgb</b> - the hex value of the RGB LEDs (000000..FFFFFF)</li>
            <li><b>rgbBrightness</b> - the brightness of the RGB LEDs in percent (0..100)</li>
            <li><b>rgbSaturation</b> - the saturation of the RGB LEDs in percent (0..100)</li>
            <li><b>rgbHue</b> - the hue of the RGB LEDs in degree (0..360)</li>
            <li><b>rgbState</b> - the state of the RGB LEDs (on | off)</li>
      </ul>
    </ul>
</ul>

=end html

=cut

