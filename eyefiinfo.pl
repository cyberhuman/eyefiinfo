#!/usr/bin/perl

#
# eyefiinfo.pl - retrieve various information for Eye-Fi cards
# Copyright (C) 2012 Roman Vorobets, https://github.com/cyberhuman
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see http://www.gnu.org/licenses/.
#

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use LWP::Simple qw(get);
use XML::Bare;
use Text::FormatTable;
use IO::Prompt;
use Getopt::Long;
use Pod::Usage;

#use Data::Dumper;

sub sig
{
  my $map = shift;
  my $str = 'e0b35b59c83efd81935127cd36a6732c';
  foreach my $key ( sort keys %$map )
  {
    $str .= $key . $map->{$key};
  }
  return md5_hex(encode_utf8($str));
}

sub url
{
  my $map = shift;
  my %map = %$map;
  my $url = 'https://api.eye.fi/api/rest/manager/1.2/?';
#  $map{'format'} = 'json'; # Use XML
  $map{'api_key'} = 'c93a7e4eb45b07e176f31906b43ed7bb';
  $map{'Locale'} = 'en_US';
  $map{'api_sig'} = sig(\%map);
  foreach my $key ( keys %map )
  {
    $url .= '&' . $key . "=" . $map{$key};
  }
  $url =~ s/&//;
  return $url;
}

sub rpc
{
  get(url(+{@_}));
}

sub check_error
{
  my $res = shift;
  return 0 if !defined $res->{'Error'};
  $res = $res->{'Error'};
  print "ERROR($res->{'Code'}): $res->{'Message'}\n";
  return 1;
}

sub auth_login
{
  my $xml = rpc(
    method => 'auth.login',
    Login => shift,
    Password => shift,
    LongSession => 0,
  );
  my $res = new XML::Bare(text => $xml)->simple();
  return undef if check_error($res);
  return $res->{'Response'}->{'User'}->{'AuthToken'};
}

sub auth_logout
{
  my $xml = rpc(
    method => 'auth.logout',
    auth_token => shift,
  );
  my $res = new XML::Bare(text => $xml)->simple();
  return undef if check_error($res);
  return $res->{'Response'};
}

sub devices_get
{
  my $xml = rpc(
    method => 'devices.get',
    auth_token => shift,
  );
  my $res = new XML::Bare(text => $xml, forcearray => [qw/Device Features/])->simple();
  return undef if check_error($res);
  return $res->{'Response'}->{'Device'};
}

sub devices_setdesktop
{
  my $xml = rpc(
    method => 'devices.setDesktop',
    auth_token => shift,
    Mac => shift,
    DesktopID => shift,
    MediaType => shift,
  );
  my $res = new XML::Bare(text => $xml)->simple();
  return undef if check_error($res);
  return $res->{'Response'}; 
}

sub List
{
  my $param = shift;
  my @columns = ( 'Type', 'Name', 'Brand', 'Mac', 'DesktopId' );
  my $table = Text::FormatTable->new(' l ' x @columns);
  $table->head(@columns);
  $table->rule;
  foreach my $dev ( @{$param->{'devices'}} )
  {
    $table->row(@$dev{@columns});
  }
  print $table->render;
  return 1;
}

sub Keys
{
  my $param = shift;
  my $rows = 0;
  my @columns = ( 'Mac', 'UploadKey', 'DownsyncKey' );
  my $table = Text::FormatTable->new(' l ' x @columns);
  $table->head(@columns);
  $table->rule;
  foreach my $dev ( @{$param->{'devices'}} )
  {
    if (1 eq $dev->{'Type'})
    {
      my $keys = devices_setdesktop($param->{'auth_key'}, @$dev{'Mac', 'DesktopId', 'Type'});
      if (defined($keys))
      {
        $keys->{'Mac'} = $dev->{'Mac'};
        $table->row(@$keys{@columns});
      } else
      {
        $table->row($dev->{'Mac'}, ('-Error-') x 2);
      }
      ++$rows;
    }
  }
  if ($rows)
  {
    print $table->render;
  } else
  {
    print "There are no applicable devices.\n";
  }
}

my $username;
my $password;
my %actions =
(
  list => sub { List(@_); },
  keys => sub { Keys(@_); },
);

GetOptions(
  'help|h|?' => sub { pod2usage(0) },
  'username:s' => \$username,
  'password:s' => \$password,
) or pod2usage(2);

my $action = shift || 'keys';
pod2usage(2) if (!defined($actions{$action}) || @ARGV);

$username = prompt('Username: ') unless $username;
$password = prompt('Password: ', -e => '') unless $password;

my $auth_key = auth_login($username, $password) or die;
my $devices = devices_get($auth_key);

if (!defined($devices))
{
  print "There are no associated devices.\n";
} else
{
  $actions{$action}(
    {
      auth_key => $auth_key,
      devices => $devices,
    }
  );
}
auth_logout($auth_key);

__END__

=head1 NAME

eyefiinfo.pl - retrieve various information for Eye-Fi cards

=head1 SYNOPSIS

eyefiinfo.pl [--help|-h|-?] [--username|-u login]
             [--password|-p password] [action]

 Options:
  --help|-h|-?  Print this help message

  --username    Specify the login on the eye.fi server

  --password    Specify the password on the eye.fi server

  If either the username or the password is not specified,
  it is read from the standard input.

 Action can be one of the following:
  list          List all associated devices
  keys          List the upload and downsync keys for
                the applicable devices. This is the default.

=cut

