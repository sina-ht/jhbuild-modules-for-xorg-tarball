#!/usr/bin/env perl
# Copyright(C) 2010 by Hiroshi Takekawa
#
# Read the current xorg.modules and create xorg.modules for a tar-ball release.

# # xorg.jhbuildrc sample
# # $ jhbuild -f xorg.jhbuildrc
# moduleset = '/tank/src/Xorg/X11R7.6-RC1.xorg.modules'
# modules = [ 'xorg' ]
# checkoutroot = '/tank/src/Xorg/X11R7.6-RC1'
# tarballdir = os.path.join(checkoutroot, 'pkgs')
# prefix = '/usr/X11R7.66-RC1'
# os.environ['ACLOCAL'] = 'aclocal -I ' + os.path.join(prefix, 'share', 'aclocal')
# os.environ['PKG_CONFIG_PATH'] = os.path.join(prefix, 'lib', 'pkgconfig') \
#                         + ':' + os.path.join(prefix, 'share', 'pkgconfig')

use LWP::UserAgent;
use XML::Simple;
use Digest;
#use Data::Dumper;

### Configuration
my $XorgTargetURL = 'http://www.x.org/releases/X11R7.6-RC1/src/everything/';
my $XorgTargetCache = '.src.everything';
my $XorgTargetCacheDir = 'X11R7.6-RC1';
my $XorgBaseURL = 'http://cgit.freedesktop.org/xorg/util/modular/plain/xorg.modules';
my $XorgBaseCache = '.xorg.modules.cache';
# source to target conversion
# SYSTEM means that we use the system-installed module.
my $XorgModules = {
    'macros' => 'util-macros',
    'x11proto' => 'xproto',
    'libxtrans' => 'xtrans',
    'pthread-stubs' => 'libpthread-stubs',
    'fonts-util' => 'font-util',
    'fontconfig' => 'SYSTEM',
    'libXRes' => 'libXres',
    'libxkbui' => 'SKIP',
    'libdrm' => 'SYSTEM',
    'libGL' => 'SYSTEM',
    'pixman' => 'SYSTEM',
    'xcb-util' => 'SKIP',
    'rendercheck' => 'SKIP',
    'scripts' => 'SKIP',
    'twm' => 'SKIP',
    'xeyes' => 'SKIP',
    'xinit' => 'SKIP',
    'xlogo' => 'SKIP',
    'bitmaps' => 'xbitmaps',
    'fonts-encodings' => 'encodings',
    'adobe-75dpi' => 'font-adobe-75dpi',
    'adobe-100dpi' => 'font-adobe-100dpi',
    'adobe-utopia-75dpi' => 'font-adobe-utopia-75dpi',
    'adobe-utopia-100dpi' => 'font-adobe-utopia-100dpi',
    'adobe-utopia-type1' => 'font-adobe-utopia-type1',
    'bitstream-75dpi' => 'font-bitstream-75dpi',
    'bitstream-100dpi' => 'font-bitstream-100dpi',
    'bitstream-type1' => 'font-bitstream-type1',
    'fonts-cursor' => 'font-cursor-misc',
    'fonts-misc' => 'font-misc-misc',
    'fonts-alias' => 'font-alias',
    'xserver' => 'xorg-server',
    'xf86-video-impact' => 'SKIP',
    'xf86-video-nouveau' => 'SKIP',
    'xf86-video-sunbw2' => 'SKIP',
    'xkeyboard-config' => 'SKIP',
};

### Code
sub use_cache_or_retrieve {
    my ($url, $cache) = @_;
    my $content;

    if (-f $cache) {
	open FILE, $cache;
	$content = join '', <FILE>;
	close FILE;
    } else {
	my $ua = LWP::UserAgent->new;
	$ua->agent("create-xorg-moduleset/0.1 ");
	my $req = HTTP::Request->new(GET => $url);
	my $res = $ua->request($req);

	if (!$res->is_success) {
	    die $res->status_line, "\n";
	}
	$content = $res->content;
	open FILE, ">$cache";
	print FILE $content;
	close FILE;
    }
    return $content;
}

sub parse_base_modules {
    return XMLin(use_cache_or_retrieve($XorgBaseURL, $XorgBaseCache), KeyAttr => [ 'id' ], ForceArray => 1);
}

sub parse_target_modules {
    my %modules;

    my $index = use_cache_or_retrieve($XorgTargetURL, $XorgTargetCache);
    my @hrefs = map { /a href=\"([^"]+)\"/o; $1; } grep(/a href.*bz2/o, split("\n", $index));
    map { /(.*)-([\d-.]+)\.tar\.bz2$/o; $modules{$1}{filename} = $_; $modules{$1}{version} = $2; } @hrefs;
    return \%modules;
}

sub get_module {
    my ($m, $base) = @_;

    if (defined($base->{metamodule}{$m})) {
	return $base->{metamodule}{$m};
    } elsif (defined($base->{autotools}{$m})) {
	return $base->{autotools}{$m};
    }
    return undef;
}

sub get_module_dep {
    my ($m, $base) = @_;

    my $module = get_module($m, $base);
    
    if (defined($module->{dependencies}[0]{dep})) {
	return $module->{dependencies}[0]{dep};
    }
    return undef;
}

sub resolve_module {
    my ($module, $base, $modules, $ordered) = @_;

    my $self_module = get_module($module, $base);
    $self_module || die "Module $module not found\n";
    $modules->{$module}{resolved} && return;

    #print STDERR "Try: $module\n";

    if (($deps = get_module_dep($module, $base))) {
	my @dep_modules;
	if (ref($deps) eq "HASH") {
	    my $dep = $deps->{'package'};
	    if (!$modules->{$dep}{resolved}) {
		#print STDERR " Recurse: $module -> $dep\n";
		resolve_module($dep, $base, $modules, $ordered);
	    }
	} else {
	    foreach $d (@{$deps}) {
		my $dep = $d->{'package'};
		$modules->{$dep}{resolved} && next;
		#print STDERR " Recurse: $module -> $dep\n";
		resolve_module($dep, $base, $modules, $ordered);
	    }
	}
    }
    #print STDERR "Resolved: $module\n";
    $modules->{$module}{resolved} = 1;
    push @{$ordered}, $module;
}

### Main
my $base = parse_base_modules;
#print Dumper($base);

my %modules;
my @ordered = ();
foreach $m (keys %{$base->{metamodule}}) {
    $modules{$m}{resolved} = 0;
    $modules{$m}{seen} = 1;
    $modules{$m}{meta} = 1;
}
foreach $m (keys %{$base->{autotools}}) {
    $modules{$m}{resolved} = 0;
    $modules{$m}{seen} = 1;
    $modules{$m}{meta} = 0;
}
resolve_module('xorg', $base, \%modules, \@ordered);
#print join("\n", @ordered);

my $target_modules = parse_target_modules;
# print "\n";
# foreach my $m (keys %{$target_modules}) {
#     printf "%s: %s: %s\n", $m, $target_modules->{$m}{filename}, $target_modules->{$m}{version};
# }

# Convesion to target modules, fetch modules, calculate hash values.
-d $XorgTargetCacheDir or mkdir $XorgTargetCacheDir;
my $md5 = Digest->new("MD5");
my $sha256 = Digest->new("SHA-256");
my %target = %{$base};
$target{tarball} = $target{autotools};
delete $target{autotools};

# Preamble
print << '__EOF__';
<?xml version="1.0" standalone="no"?> <!--*- mode: nxml -*-->
<!DOCTYPE moduleset SYSTEM "moduleset.dtd">
<?xml-stylesheet type="text/xsl" href="moduleset.xsl"?>
__EOF__

foreach my $m (@ordered) {
    my $tm;
    if ($modules{$m}{meta}) {
	#print STDERR "*** $m is a meta module, skip.\n";
	next;
    }
    if (defined($target_modules->{$m}{filename})) {
	$tm = $m;
    } elsif (defined($XorgModules->{$m})) {
	if ($XorgModules->{$m} eq "SYSTEM") {
	    print "<!-- $m is a system module, skip. -->\n";
	    delete $target{tarball}{$m};
	    $target{metamodule}{$m} = {};
	    next;
	}
	if ($XorgModules->{$m} eq "SKIP") {
	    print "<!-- $m is specified as 'SKIP', skip. -->\n";
	    delete $target{tarball}{$m};
	    $target{metamodule}{$m} = {};
	    next;
	}
	$tm = $XorgModules->{$m};
	defined($target_modules->{$tm}{filename}) || die "Cannot find $m -> $tm\n";
    } else {
	die "Cannot find $m\n";
    }
    $target_modules->{$m}{targetname} = $tm;
    $target_modules->{$m}{url} = join('', $XorgTargetURL, $target_modules->{$tm}{filename});
    $target_modules->{$m}{cache} = join('/', $XorgTargetCacheDir, $target_modules->{$tm}{filename});
    #printf STDERR "%s(%s): %s: %s\n", $m, $tm, $target_modules->{$tm}{filename}, $target_modules->{$tm}{version};
    # unless (-f $target_modules->{$m}{cache}) {
    # 	print STDERR "Retrieve: $target_modules->{$m}{url}\n";
    # }
    my $data = use_cache_or_retrieve($target_modules->{$m}{url}, $target_modules->{$m}{cache});
    $md5->add($data);
    $sha256->add($data);
    $target_modules->{$m}{md5} = $md5->hexdigest;
    $target_modules->{$m}{sha256} = $sha256->hexdigest;
    $target{tarball}{$m}{source} = {
	'href' => $target_modules->{$m}{url},
	'hash' => "sha256:" . $target_modules->{$m}{sha256},
	'md5sum' => $target_modules->{$m}{md5},
	'size' => -s $target_modules->{$m}{cache},
    };
    $target{tarball}{$m}{branch} = undef;
}

# Output xorg.modules.
#print Dumper(\%target);
print XMLout(\%target, RootName => "moduleset", KeyAttr => [ 'id' ]);
