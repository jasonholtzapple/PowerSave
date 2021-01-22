package Plugins::PowerSave::Settings;

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;
use Slim::Utils::Log;

my $prefs = preferences('plugin.powersave');

my $timeDefault     = 900;
my $playmodeDefault = 0;

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_POWERSAVE');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/PowerSave/settings/player.html');
}

sub needsClient {
    return 1;
}

sub prefs {
    my ($class, $client) = @_;

    return ($prefs->client($client), qw(enabled time playmode));
}

sub handler {
    my ($class, $client, $params) = @_;

    if (!defined($prefs->client($client)->get('enabled'))) {
        $prefs->client($client)->set('enabled', 0);
    }
    if (!defined($prefs->client($client)->get('time'))) {
        $prefs->client($client)->set('time', $timeDefault);
    }
    if (!defined($prefs->client($client)->get('playmode'))) {
        $prefs->client($client)->set('playmode', $playmodeDefault);
    }

    if ($params->{'saveSettings'}) {
        if ($params->{'enabled'} == 1) {
            $prefs->client($client)->set('enabled', 1);
        } else {
            $prefs->client($client)->set('enabled', 0);
        }
        $prefs->client($client)->set('time', $params->{'time'});
        $prefs->client($client)->set('playmode', $params->{'playmode'});
    }

    $params->{'enabled'}  = $prefs->client($client)->get('enabled');
    $params->{'time'}     = $prefs->client($client)->get('time');
    $params->{'playmode'} = $prefs->client($client)->get('playmode');

    return $class->SUPER::handler($client, $params);
}

1;
