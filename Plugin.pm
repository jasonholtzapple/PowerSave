# PowerSave by Jason Holtzapple (jasonholtzapple@gmail.com)
# with contributions by Daniel Born
#
# PowerSave will turn off a player after a specified amount of idle
# time has elapsed. By default, idle time is defined as when a player
# is not playing and no button presses have been received within the
# specified time. The default idle time is 15 minutes.
#
# All settings are accessed in the Player menus.
#
# Some code and concepts were copied from these plugins:
#
# Rescan.pm by Andrew Hedges (andrew@hedges.me.uk)
# Timer functions added by Kevin Deane-Freeman (kevindf@shaw.ca)
#
# QuickAccess.pm by Felix Mueller <felix.mueller(at)gwendesign.com>
#
# And from the AlarmClock module by Kevin Deane-Freeman (kevindf@shaw.ca)
# Lukas Hinsch and Dean Blackketter
#
# This code is derived from code with the following copyright message:
#
# SliMP3 Server Copyright (C) 2001 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
#-> Changelog
#
# 7.4.1 - 25/11/2020
#    FIX: Players powersaving too early when mode is PowerSave Always
# 7.4 - 15/11/2009
#    RFE: Silence server 7.4 CSRF warnings
# 7.0r1 - 4/9/2008
#    RFE: Web interface for player settings
# 7.0a3 - 5/4/2008
#    RFE: Fix Plugin MaxVersion for SC 7.1+ (no code changes)
# 7.0a2 - 25/11/2007
#    RFE: SqueezeCenter 7.0 ready
# 6.5r3 - 28/7/2007
#    BUG: Fix for players powersaving too early
#    RFE: Add debugging messages (enabled with d_plugin)
# 6.5r2 - 30/10/2006
#    RFE: Reset idle timer on stop/non-stop transition (contributed by
#    Daniel Born)
# 6.5 - 12/9/2006
#    RFE: SlimServer v6.5 ready
# 1.0.3 - 9/3/2005
#    RFE: SlimServer v6 ready
# 1.0.2 - 9/9/2004
#    RFE: New setting to choose which playmodes will allow powersave
#    BUG: Fix 'uninitialized value' warnings
# 1.0.1 - 28/8/2004
#    BUG: Fix crashers in pre-5.3beta servers
# 1.0 - 27/8/2004 - Initial Release
#
#-> Preference Reference
#
# plugin_PowerSave_enabled
# 0 = disabled (default)
# 1 = enabled
#
# plugin_PowerSave_time
# n = number of idle seconds to PowerSave (default 900 seconds)
#
# plugin_PowerSave_playmode
# 0 = PowerSave on Pause or Stop (default)
# 1 = PowerSave on Stop
# 2 = PowerSave always

use strict;

package Plugins::PowerSave::Plugin;

use base qw(Slim::Plugin::Base);

use Plugins::PowerSave::Settings;

use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc;
use Slim::Utils::Log;
use Slim::Utils::Prefs;

use vars qw($VERSION);
$VERSION = '7.4.1';

my $log = Slim::Utils::Log->addLogCategory(
	{
		'category' => 'plugin.powersave',
		'defaultLevel' => 'WARN',
		'description' => 'PLUGIN_POWERSAVE'
	}
);

my $myPrefs = preferences('plugin.powersave');

# plugin timer interval in seconds
my $interval             = 60; 
# default powersave time
my $timeDefault          = 900;
# default powersave playmode
my $playmodeDefault      = 0;

# regex to match playmode
my @powersavePlaymode = (
	'pause|stop',
	'stop',
	'.*',
);

my @browseMenuChoices = ();
my %menuSelection     = ();
my %powerSaveTimers   = ();

sub initPlugin {
	my $class = shift;
	
	$class->SUPER::initPlugin();

	Plugins::PowerSave::Settings->new();
	
	setTimer();
}

sub setMode {
	my $class = shift;
	my $client = shift;
	my $method = shift;

#	if ($method eq 'pop') {
#		Slim::Buttons::Common::popMode($client);
#		return;
#	}

	@browseMenuChoices = (
		string('PLUGIN_POWERSAVE_OFF'),
		string('PLUGIN_POWERSAVE_TIMER_SET_MENU'),
		string('PLUGIN_POWERSAVE_PLAYMODE_MENU'),
	);

	unless (defined($menuSelection{$client})) {
		$menuSelection{$client} = 0;
	};

	$client->lines(\&lines);
}

sub getDisplayName() {
	return 'PLUGIN_POWERSAVE';
}

my %functions = (
	'up' => sub {
		my $client = shift;

		my $newposition = Slim::Buttons::Common::scroll
			($client, -1, ($#browseMenuChoices + 1),
			$menuSelection{$client});
		$menuSelection{$client} = $newposition;
		$client->update();
	},
	'down' => sub {
		my $client = shift;

		my $newposition = Slim::Buttons::Common::scroll
			($client, +1, ($#browseMenuChoices + 1),
			$menuSelection{$client});
		$menuSelection{$client} = $newposition;
		$client->update();
	},
	'left' => sub {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub {
		my $client = shift;

		my @menuTimerChoices = (
			string('PLUGIN_POWERSAVE_INTERVAL_1'),
			string('PLUGIN_POWERSAVE_INTERVAL_2'),
			string('PLUGIN_POWERSAVE_INTERVAL_3'),
			string('PLUGIN_POWERSAVE_INTERVAL_4'),
			string('PLUGIN_POWERSAVE_INTERVAL_5'),
			string('PLUGIN_POWERSAVE_INTERVAL_6'),
		);

		my @menuTimerIntervals =
			map { 60 * ($_ =~ /(\d+)/)[0] } @menuTimerChoices;

		my @menuPlaymode = (
			string('PLUGIN_POWERSAVE_PLAYMODE_1'),
			string('PLUGIN_POWERSAVE_PLAYMODE_2'),
			string('PLUGIN_POWERSAVE_PLAYMODE_3'),
		);

		if ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_POWERSAVE_OFF')) {
			$myPrefs->client($client)->set('enabled', 1);
			$browseMenuChoices[$menuSelection{$client}] =
				string('PLUGIN_POWERSAVE_ON');
			$client->showBriefly({
				'line'    => [string('PLUGIN_POWERSAVE_TURNING_ON'), ''],
			});
		} elsif ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_POWERSAVE_ON')) {
			$myPrefs->client($client)->set('enabled', 0);
			$browseMenuChoices[$menuSelection{$client}] =
				string('PLUGIN_POWERSAVE_OFF');
			$client->showBriefly({
				'line'    => [string('PLUGIN_POWERSAVE_TURNING_OFF'), ''],
			});
		} elsif ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_POWERSAVE_TIMER_SET_MENU')) {
			my %params = (
				'listRef' => [ @menuTimerIntervals ],
				'externRef' => [ @menuTimerChoices ],
				'header' => string('PLUGIN_POWERSAVE_TIMER_SET_MENU'),
				'valueRef' => \ ($myPrefs->client($client)->get('time') || $timeDefault),
				'onChange' => sub { $myPrefs->client($_[0])->set('time', $_[1])},
				'onChangeArgs' => 'CV',
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
		} elsif ($browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_POWERSAVE_PLAYMODE_MENU')) {
			my %params = (
				'listRef' => [ 0, 1, 2 ],
				'externRef' => [ @menuPlaymode ],
				'header' => string('PLUGIN_POWERSAVE_PLAYMODE_MENU'),
				'valueRef' => \ ($myPrefs->client($client)->get('playmode') || $playmodeDefault),
				'onChange' => sub { $myPrefs->client($_[0])->set('playmode', $_[1])},
				'onChangeArgs' => 'CV',
			);
			Slim::Buttons::Common::pushModeLeft($client, 'INPUT.List', \%params);
		}
	},
);

sub getFunctions() {
	my $class = shift;

	return \%functions;
}

sub lines {
	my $client = shift;

	my ($line1, $line2);

	$line1 = string('PLUGIN_POWERSAVE');

	if ($myPrefs->client($client)->get('enabled') &&
		$browseMenuChoices[$menuSelection{$client}] eq string('PLUGIN_POWERSAVE_OFF')) {
		$browseMenuChoices[$menuSelection{$client}] =
			string('PLUGIN_POWERSAVE_ON');
	}
	$line2 = '';

	$line2 = $browseMenuChoices[$menuSelection{$client}];
	return {
		'line' => [$line1, $line2],
		'overlay' => [undef, $client->symbols('rightarrow')]
	};
}

sub checkPlaymode {
	my $client = shift;

	my $setting = $myPrefs->client($client)->get('playmode') || $playmodeDefault;
	if ($setting < 0 or $setting > 2) { $setting = $playmodeDefault }
	my $mode    = Slim::Player::Source::playmode ($client);

	if ($mode =~ /^$powersavePlaymode[$setting]$/) {
		return 1;
	} else {
		return 0;
	}
}

sub checkPowerSaveTimer {

	foreach my $client (Slim::Player::Client::clients()) {

		unless (exists $powerSaveTimers{$client}) {
			$powerSaveTimers{$client}{time} = time;
			$powerSaveTimers{$client}{modechgtime} = 0;
			$powerSaveTimers{$client}{lastirtime} = int ($client->lastirtime);
			$powerSaveTimers{$client}{psactivated} = 0;
			$powerSaveTimers{$client}{playmode} = '';
		}

		$log->debug("PowerSave state info for client $client\nmode: @{[Slim::Buttons::Common::mode ($client)]}\nplaymode: @{[Slim::Player::Source::playmode ($client)]}\n");

		if ((Slim::Buttons::Common::mode ($client) !~ /^OFF/)
			and ($myPrefs->client($client)->get('enabled'))) {
		        my $curplaymode = Slim::Player::Source::playmode ($client);
			if ($powerSaveTimers{$client}{playmode} ne $curplaymode) {
				$log->debug("PowerSave client playmode change. Sync playmode and update modechgtime\n");
				$powerSaveTimers{$client}{playmode} = $curplaymode;
				$powerSaveTimers{$client}{modechgtime} = 0;
			}
			if (checkPlaymode ($client)) {
				my $time = $myPrefs->client($client)->get('time') || $timeDefault;
				$log->debug("PowerSave check: client eligible for sleep: powersave-time=${time}\n");
				# reset timer after wakeup
				if ($powerSaveTimers{$client}{psactivated} == 1) {
					$powerSaveTimers{$client}{time} = time;
					$powerSaveTimers{$client}{psactivated} = 0;
					$log->debug("PowerSave nosleep: reset timer after wakeup\n");
				} elsif ($powerSaveTimers{$client}{lastirtime} != int ($client->lastirtime)) {
					$powerSaveTimers{$client}{lastirtime} = int ($client->lastirtime);
					$powerSaveTimers{$client}{time} = time;
					$log->debug("PowerSave nosleep: ir activity: lastirtime=${powerSaveTimers{$client}{lastirtime}}\n");
				} elsif ($powerSaveTimers{$client}{modechgtime} == 0) {
					$powerSaveTimers{$client}{modechgtime} = time;
					$log->debug("PowerSave nosleep: mode change: modechgtime=${powerSaveTimers{$client}{modechgtime}}\n");
				} elsif ((int(time - $powerSaveTimers{$client}{time}) >= $time)
					and (int(time - $powerSaveTimers{$client}{modechgtime}) >= $time)) {
					$powerSaveTimers{$client}{psactivated} = 1;
					$client->execute(['power', 0]);
					$log->debug("PowerSave sleep at @{[int(time)]} : time=${powerSaveTimers{$client}{time}} modechgtime=${powerSaveTimers{$client}{modechgtime}}\n");
				}
			}
		}
	}
	setTimer ();
}

sub setTimer {
	Slim::Utils::Timers::setTimer (0, time + $interval, \&checkPowerSaveTimer);
}

1;
