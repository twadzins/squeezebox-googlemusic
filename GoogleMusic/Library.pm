package Plugins::GoogleMusic::Library;

use strict;
use warnings;

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);

use Slim::Utils::Prefs;
use Slim::Utils::Log;
use Slim::Utils::Cache;

use Plugins::GoogleMusic::GoogleAPI;

my $log = logger('plugin.googlemusic');
my $prefs = preferences('plugin.googlemusic');
my $googleapi = Plugins::GoogleMusic::GoogleAPI::get();

# Database for tracks, albums, and artists indexed by URIs
my $tracks = {};
my $albums = {};
my $artists = {};

# Reload and reparse your music collection
sub refresh {
	my $songs;

	if (!$googleapi->is_authenticated()) {
		return;
	}
	
	# Clear the database
	$tracks = {};
	$albums = {};
	$artists = {};

	# Reload from Google
	$songs = $googleapi->get_all_songs();
	# Initialize
	for my $song (@{$songs}) {
		to_slim_track($song);
	}

	return;
}

sub search {
	my $query = shift;

	my $tracks = search_tracks($query);
	my $albums = {};
	my $artists = {};

	for my $track (@$tracks) {
		$albums->{$track->{album}->{uri}} = $track->{album};
		$artists->{$track->{artist}->{uri}} = $track->{artist};
		$artists->{$track->{album}->{artist}->{uri}} = $track->{album}->{artist};
	}

	return ($tracks, [values %$albums], [values %$artists]);
}

sub search_tracks {
	my $query = shift;

	if (!$query) {
		$query = {};
	}

	my @result = values %{$tracks};

	while (my ($key, $values) = each %{$query} ) {
		if (ref($values) ne 'ARRAY') {
			$values = [$values];
		}
		for my $value (@{$values}) {

			# TODO: Need to strip $value first
			my $q = lc($value);

			my $track_filter = sub { lc($_->{title}) =~ $q };
			my $album_filter = sub { lc($_->{album}->{name}) =~ $q };
			my $artist_filter = sub { lc($_->{artist}->{name}) =~ $q || lc($_->{album}->{artist}->{name}) =~ $q};
			my $year_filter = sub { $_->{year} == $q };
			my $any_filter = sub { &$track_filter($_) || &$album_filter($_) || &$artist_filter($_) };

			if ($key eq 'track') {
				@result = grep { &$track_filter($_) } @result;
			} elsif ($key eq 'album') {
				@result = grep { &$album_filter($_) } @result;
			} elsif ($key eq 'artist') {
				@result = grep { &$artist_filter($_) } @result;
			} elsif ($key eq 'year') {
				@result = grep { &$year_filter($_) } @result;
			} elsif ($key eq 'any') {
				@result = grep { &$any_filter($_) } @result;
			}
		}
	}
	return \@result;
}


sub find_exact {
	my $query = shift;

	my $tracks = find_exact_tracks($query);
	my $albums = {};
	my $artists = {};

	for my $track (@$tracks) {
		$albums->{$track->{album}->{uri}} = $track->{album};
		$artists->{$track->{artist}->{uri}} = $track->{artist};
		$artists->{$track->{album}->{artist}->{uri}} = $track->{album}->{artist};
	}

	return ($tracks, [values %$albums], [values %$artists]);
}

sub find_exact_tracks {
	my $query = shift;

	if (!$query) {
		$query = {};
	}

	my @result = values %{$tracks};

	while (my ($key, $values) = each %{$query} ) {
		if (ref($values) ne 'ARRAY') {
			$values = [$values];
		}
		for my $value (@{$values}) {

			# TODO: Need to strip $value first
			my $q = $value;

			my $track_filter = sub { $_->{title} eq $q };
			my $album_filter = sub { $_->{album}->{name} eq $q };
			my $artist_filter = sub { $_->{artist}->{name} eq $q || $_->{album}->{artist}->{name} eq $q};
			my $year_filter = sub { $_->{year} == $q };
			my $any_filter = sub { &$track_filter($_) || &$album_filter($_) || &$artist_filter($_) };

			if ($key eq 'track') {
				@result = grep { &$track_filter($_) } @result;
			} elsif ($key eq 'album') {
				@result = grep { &$album_filter($_) } @result;
			} elsif ($key eq 'artist') {
				@result = grep { &$artist_filter($_) } @result;
			} elsif ($key eq 'year') {
				@result = grep { &$year_filter($_) } @result;
			} elsif ($key eq 'any') {
				@result = grep { &$any_filter($_) } @result;
			}
		}
	}
	return \@result;
}

sub get_track {
	my $uri = shift;

	if ($uri =~ '^googlemusic:track:T') {
		return Plugins::GoogleMusic::AllAccess::get_track($uri);
	} else {
		return $tracks->{$uri};
	}
}

sub get_track_by_id {
	my $id = shift;

	if ($id =~ '^T') {
		return Plugins::GoogleMusic::AllAccess::get_track_by_id($id);
	} else {
		return get_track('googlemusic:track:' . $id);
	}
}

sub get_album {
	my $uri = shift;

	if ($uri =~ '^googlemusic:album:B') {
		return Plugins::GoogleMusic::AllAccess::get_album_info($uri);
	} else {
		return $albums->{$uri};
	}
}

sub get_artist {
	my $uri = shift;

	if ($uri =~ '^googlemusic:artist:A') {
		return Plugins::GoogleMusic::AllAccess::get_artist_info($uri);
	} else {
		return $artists->{$uri};
	}
}

# Convert a Google Music Song dictionary to a consistent
# robust track representation
sub to_slim_track {
	my $song = shift;

	my $uri = 'googlemusic:track:' . $song->{id};
	if (exists $tracks->{$uri}) {
		return $tracks->{$uri};
	}

	my $cover = '/html/images/cover.png';
	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
		$cover = Plugins::GoogleMusic::Image->uri($cover);
	}

	# Get/create the album for this song
	my $album = to_slim_album($song);

	# Build track info
	my $track = {
		uri => $uri,
		title => $song->{title},
		album => $album,
		artist => to_slim_artist($song),
		year => $song->{year} || 0,
		cover => $cover,
		secs => $song->{durationMillis} / 1000,
		bitrate => 320,
		genre => $song->{genre},
		filesize => $song->{estimatedSize},
		trackNumber => $song->{trackNumber} || 1,
		discNumber => $song->{discNumber} || 1,
	};

	# Add the track to the album track list
	push @{$album->{tracks}}, $track;

	# Add the track to the track database
	$tracks->{$uri} = $track;

	return $track;
}

# Convert a Google Music Song dictionary to a consistent
# robust album representation
sub to_slim_album {
	my $song = shift;

	my $artist = to_slim_album_artist($song);
	my $name = $song->{album};
	my $year = $song->{year} || 0;

	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($artist->{name} . $name . $year);
	my $uri = 'googlemusic:album:' . $id;
	if (exists $albums->{$uri}) {
		return $albums->{$uri};
	}

	my $cover = '/html/images/cover.png';
	if (exists $song->{albumArtRef}) {
		$cover = $song->{albumArtRef}[0]{url};
		$cover = Plugins::GoogleMusic::Image->uri($cover);
	}

	my $album = {
		uri => $uri,
		name => $name,
		artist => $artist,
		year => $year,
		cover => $cover,
		tracks => [],
	};

	$albums->{$uri} = $album;

	return $album;
}

# Convert a Google Music Song dictionary to a consistent
# robust artist representation
sub to_slim_artist {
	my $song = shift;

	my $name = $song->{artist};
	
	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($name);
	my $uri = 'googlemusic:artist:' . $id;
	if (exists $artists->{$uri}) {
		return $artists->{$uri};
	}

	my $image = '/html/images/artists.png';
	if (exists $song->{artistArtRef}) {
		$image = $song->{artistArtRef}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}

	my $artist = {
		uri => $uri,
		name => $name,
		image => $image,
	};

	$artists->{$uri} = $artist;

	return $artist;
}

# Convert a Google Music Song dictionary to a consistent
# robust album artist representation
sub to_slim_album_artist {
	my $song = shift;

	# In one test case (the band 'Poliça') GoogleMusic messed up the
	# 'artist' is sometime lowercase, where the 'albumArtist' is
	# uppercase the albumArtist is the most consistent so take that or
	# else we will see multiple entries in the Artists listing (lower
	# + upper case)
	my $name = $song->{albumArtist} || $song->{artist};
	
	# Better create an ID by ourself. IDs in My Library are not
	# consistent and are not always present
	my $id = _create_id($name);
	my $uri = 'googlemusic:artist:' . $id;
	if (exists $artists->{$uri}) {
		return $artists->{$uri};
	}

	my $image = '/html/images/artists.png';
	# Check to see if this album is a compilation from various
	# artists. The Google Music webinterface also shows a 'Various
	# artists' in my library instead of all seperate artists.. which
	# should justify this functionality
	my $various = (index(lc($song->{artist}), lc($song->{albumArtist} || '')) == -1) ? 1 : 0;
	if (exists $song->{artistArtRef} and not $various) {
		$image = $song->{artistArtRef}[0]{url};
		$image = Plugins::GoogleMusic::Image->uri($image);
	}
	
	my $artist = {
		uri => $uri,
		name => $name,
		various => $various,
		image => $image,
	};

	$artists->{$uri} = $artist;

	return $artist;
}

sub _create_id {
	my $str = shift;

	return md5_hex(encode_utf8($str));
}

1;
