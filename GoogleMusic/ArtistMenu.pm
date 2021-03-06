package Plugins::GoogleMusic::ArtistMenu;

use strict;
use warnings;

use Slim::Utils::Log;
use Slim::Utils::Strings qw(cstring);

use Plugins::GoogleMusic::Plugin;
use Plugins::GoogleMusic::TrackMenu;
use Plugins::GoogleMusic::AlbumMenu;


my $log = logger('plugin.googlemusic');


sub feed {
	my ($client, $callback, $args, $artists, $opts) = @_;

	return $callback->(menu($client, $args, $artists, $opts));
}

sub menu {
	my ($client, $args, $artists, $opts) = @_;

	my @items;

	if ($opts->{sortArtists}) {
		@$artists = sort { lc($a->{name}) cmp lc($b->{name}) } @$artists;
	}

	for my $artist (@{$artists}) {
		push @items, _showArtist($client, $artist, $opts);
	}

	if (!scalar @items) {
		push @items, {
			name => cstring($client, 'EMPTY'),
			type => 'text',
		}
	}

	return {
		items => \@items,
	};
}

sub _showArtist {
	my ($client, $artist, $opts) = @_;

	my $item = {
		name => $artist->{name},
		image => $artist->{image},
		type => 'link',
		url => \&_artistMenu,
		passthrough => [ $artist, $opts ],
		itemActions => {
			allAvailableActionsDefined => 1,
			items => {
				command     => ['googlemusicbrowse', 'items'],
				fixedParams => { uri => $artist->{uri} },
			},
		},
	};

	# If the artists are sorted by name add a text key to easily jump
	# to artists on squeezeboxes
	if ($opts->{sortArtists}) {
		$item->{textkey} = substr($artist->{name}, 0, 1);
	}

	return $item;
}


sub _artistMenu {
	my ($client, $callback, $args, $artist, $opts) = @_;

	if ($opts->{all_access} || $artist->{uri} =~ '^googlemusic:artist:A') {
		my $info = Plugins::GoogleMusic::AllAccess::get_artist_info($artist->{uri});

		if (!$info) {
			$callback->(Plugins::GoogleMusic::Plugin::errorMenu($client));
			return;
		}

		if ($opts->{mode}) {
			if ($opts->{mode} eq 'albums') {
				Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $info->{albums}, { all_access => 1, sortAlbums => 1 } );
				return;
			} elsif ($opts->{mode} eq 'tracks') {
				Plugins::GoogleMusic::TrackMenu::feed($client, $callback, $args, $info->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1, playall_uri => $artist->{uri} });
				return;
			} elsif ($opts->{mode} eq 'artists') {
				Plugins::GoogleMusic::ArtistMenu::feed($client, $callback, $args, $info->{related}, { } );
				return;
			}
		}

		my @items = ( {
			name => cstring($client, "ALBUMS") . " (" . scalar @{$info->{albums}} . ")",
			type => 'link',
			url => \&Plugins::GoogleMusic::AlbumMenu::feed,
			itemActions => {
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'albums', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{albums}, { all_access => 1, sortAlbums => 1 } ],
		}, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_TOP_TRACKS") . " (" . scalar @{$info->{tracks}} . ")",
			type => 'playlist',
			url => \&Plugins::GoogleMusic::TrackMenu::feed,
			itemActions => {
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'tracks', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{tracks}, { all_access => 1, showArtist => 1, showAlbum => 1, playall => 1, playall_uri => $artist->{uri} } ],
		}, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_RELATED_ARTISTS") . " (" . scalar @{$info->{related}} . ")",
			type => 'link',
			url => \&feed,
			itemActions => {
				allAvailableActionsDefined => 1,
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'artists', uri => $artist->{uri} },
				},
			},
			passthrough => [ $info->{related}, $opts ],
		} );

		if (exists $info->{artistBio}) {
			push @items, {
				name => cstring($client, "PLUGIN_GOOGLEMUSIC_BIOGRAPHY"),
				type => 'link',
				items => [ { name => $info->{artistBio}, type => 'text', wrap => 1 } ],
			}
		}
		
		(my $radioURI = $artist->{uri}) =~ s/googlemusic/googlemusicradio/;

		push @items, {
			name => cstring($client, "PLUGIN_GOOGLEMUSIC_START_RADIO"),
			type => 'audio',
			url => $radioURI,
			cover => $artist->{image},
		};

		$callback->({
			items => \@items,
			cover => $artist->{image},
			actions => {
				allAvailableActionsDefined => 1,
				items => {
					command     => ['googlemusicbrowse', 'items'],
					fixedParams => { mode => 'tracks', uri => $artist->{uri} },
				},
			},
		});
	} else {
		my ($tracks, $albums, $artists) = Plugins::GoogleMusic::Library::find_exact({artist => $artist->{name}});

		Plugins::GoogleMusic::AlbumMenu::feed($client, $callback, $args, $albums, $opts);
	}

	return;
}

1;
