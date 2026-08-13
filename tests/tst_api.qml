import QtQuick
import QtTest

import "../Api.js" as Api

TestCase {
  name: "SpotifyApiLogic"

  function test_queryString_isStableAndEncoded() {
    compare(Api.queryString({ z: "last", q: "AC/DC & friends", empty: "" }),
      "q=AC%2FDC%20%26%20friends&z=last")
  }

  function test_spotifydVolumeCurve_hasStableEndpointsAndRoundTrips() {
    compare(Api.spotifydVolumeToSlider(0), 0)
    compare(Api.spotifydVolumeToSlider(1), 1)
    compare(Api.sliderToSpotifydVolume(0), 0)
    compare(Api.sliderToSpotifydVolume(1), 1)

    var positions = [0.01, 0.1, 0.25, 0.5, 0.75, 0.9]
    for (var i = 0; i < positions.length; i++) {
      var slider = positions[i]
      var backend = Api.sliderToSpotifydVolume(slider)
      verify(Math.abs(Api.spotifydVolumeToSlider(backend) - slider) < 0.000001)
    }
  }

  function test_spotifydVolumeCurve_usesGentlerCubicTaper() {
    var backendMidpoint = Api.sliderToSpotifydVolume(0.5)
    verify(backendMidpoint > 0.73 && backendMidpoint < 0.75)
    verify(Api.spotifydVolumeToSlider(0.5) < 0.25)
  }

  function test_normalizeVolumePercent_preservesUnknownAndValidMute() {
    compare(Api.normalizeVolumePercent(null), null)
    compare(Api.normalizeVolumePercent(undefined), null)
    compare(Api.normalizeVolumePercent(""), null)
    compare(Api.normalizeVolumePercent("not-a-volume"), null)
    compare(Api.normalizeVolumePercent(0), 0)
    compare(Api.normalizeVolumePercent(47), 47)
    compare(Api.normalizeVolumePercent(120), 100)
  }

  function test_catalogSearchText_scopesResultsToArtist() {
    compare(Api.catalogSearchText("Miles Davis", "blue in green"),
      "blue in green artist:\"Miles Davis\"")
    compare(Api.catalogSearchText("AC/DC \"Live\"", ""),
      "artist:\"AC/DC Live\"")
  }

  function test_tracksForArtist_filtersBroadSearchByStableArtistId() {
    var rows = Api.tracksForArtist([
      { id: "solo", type: "track", artists: [{ id: "target", name: "Artist" }] },
      { id: "feature", type: "track", artists: [
        { id: "guest", name: "Guest" }, { id: "target", name: "Artist" }
      ] },
      { id: "tribute", type: "track", artists: [{ id: "other", name: "Artist" }] },
      { id: "album", type: "album", artists: [{ id: "target", name: "Artist" }] }
    ], { id: "target", name: "Artist" })

    compare(rows.length, 2)
    compare(rows[0].id, "solo")
    compare(rows[1].id, "feature")
  }

  function test_findThisIsPlaylist_requiresExactTitleAndPrefersSpotify() {
    var result = Api.findThisIsPlaylist([
      { id: "lookalike", type: "playlist", name: "This Is Nearly Björk", ownerName: "Spotify" },
      { id: "fan", type: "playlist", name: "THIS IS BJÖRK!", ownerName: "A listener" },
      { id: "official", type: "playlist", name: "This Is Björk", ownerId: "spotify" }
    ], "Björk")

    verify(result !== null)
    compare(result.id, "official")
    compare(Api.findThisIsPlaylist([
      { id: "wrong", type: "playlist", name: "Best of Björk", ownerName: "Spotify" }
    ], "Björk"), null)
  }

  function test_trackRadioPlaylists_onlyKeepsExactSpotifyContexts() {
    var result = Api.trackRadioPlaylists([
      { id: "official", uri: "spotify:playlist:official", type: "playlist",
        name: "Dreams - 2004 Remaster Radio", ownerId: "spotify" },
      { id: "copy", uri: "spotify:playlist:copy", type: "playlist",
        name: "Dreams - 2004 Remaster Radio", ownerName: "A listener" },
      { id: "other", uri: "spotify:playlist:other", type: "playlist",
        name: "Sunset Dreams - 2004 Remaster Radio", ownerName: "Spotify" }
    ], "Dreams - 2004 Remaster")

    compare(result.length, 1)
    compare(result[0].id, "official")
  }

  function test_radioSeedMatches_acceptsRelinkedTrackFromSameArtist() {
    verify(Api.radioSeedMatches({
      id: "market-version", uri: "spotify:track:market-version",
      name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }, { id: "rihanna", name: "Rihanna" }]
    }, {
      id: "original", uri: "spotify:track:original",
      name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }]
    }))
    verify(!Api.radioSeedMatches({
      id: "cover", name: "Love The Way You Lie",
      artists: [{ id: "cover-band", name: "Cover Band" }]
    }, {
      id: "original", name: "Love The Way You Lie",
      artists: [{ id: "eminem", name: "Eminem" }]
    }))
  }

  function test_discoveryPlaylists_keepsOfficialRelevantResultsInUsefulOrder() {
    var rows = Api.discoveryPlaylists([
      { id: "fan", type: "playlist", name: "Discover Weekly", ownerName: "A listener" },
      { id: "fresh", uri: "spotify:playlist:fresh", type: "playlist",
        name: "Fresh Finds Indie", ownerName: "Spotify" },
      { id: "mix", uri: "spotify:playlist:mix", type: "playlist",
        name: "Daily Mix 2", ownerId: "spotify" },
      { id: "radar", uri: "spotify:playlist:radar", type: "playlist",
        name: "Release Radar", ownerName: "Spotify" },
      { id: "weekly", uri: "spotify:playlist:weekly", type: "playlist",
        name: "Discover Weekly", ownerName: "Spotify" },
      { id: "weekly", uri: "spotify:playlist:weekly", type: "playlist",
        name: "Discover Weekly", ownerName: "Spotify" },
      { id: "unrelated", type: "playlist", name: "Party Hits", ownerName: "Spotify" }
    ])

    compare(rows.length, 4)
    compare(rows[0].id, "weekly")
    compare(rows[1].id, "radar")
    compare(rows[2].id, "mix")
    compare(rows[3].id, "fresh")
  }

  function test_scopes_followLeastPrivilege() {
    verify(Api.SCOPES.indexOf("user-modify-playback-state") >= 0)
    verify(Api.SCOPES.indexOf("user-library-read") >= 0)
    verify(Api.SCOPES.indexOf("user-follow-read") >= 0)
    verify(Api.SCOPES.indexOf("user-read-recently-played") >= 0)
    verify(Api.SCOPES.indexOf("user-top-read") >= 0)
    verify(Api.SCOPES.indexOf("playlist-modify-private") >= 0)
    verify(Api.SCOPES.indexOf("playlist-modify-public") >= 0)
    verify(Api.SCOPES.indexOf("user-read-private") === -1)
    verify(Api.SCOPES.indexOf("user-read-email") === -1)
    verify(Api.SCOPES.indexOf("user-read-currently-playing") === -1)
  }

  function test_safeApiUrl_rejectsForeignHosts() {
    compare(Api.safeApiUrl("/me"), Api.API_BASE + "/me")
    compare(Api.safeApiUrl(Api.API_BASE + "/me/tracks"), Api.API_BASE + "/me/tracks")
    compare(Api.safeApiUrl("https://api.spotify.com.evil.example/v1/me"), "")
    compare(Api.safeApiUrl("https://example.com/v1/me"), "")
  }

  function test_normalizeTrack_supportsCurrentPlaylistItems() {
    var normalized = Api.normalizeTrack({
      item: {
        id: "track-id",
        uri: "spotify:track:track-id",
        type: "track",
        name: "A track",
        duration_ms: 123000,
        explicit: true,
        artists: [{ name: "One" }, { name: "Two" }],
        album: {
          name: "An album",
          images: [
            { url: "large", width: 640 },
            { url: "small", width: 64 },
            { url: "right-sized", width: 96 }
          ]
        },
        external_urls: { spotify: "https://open.spotify.com/track/track-id" }
      }
    }, 96)

    verify(normalized !== null)
    compare(normalized.name, "A track")
    compare(normalized.subtitle, "One, Two")
    compare(normalized.album, "An album")
    compare(normalized.imageUrl, "right-sized")
    compare(normalized.durationMs, 123000)
    compare(normalized.explicit, true)
    compare(normalized.artists.length, 2)
    compare(normalized.albumItem.name, "An album")
    compare(normalized.albumItem.type, "album")
  }

  function test_normalizeTrack_supportsEpisodesAndResumePosition() {
    var episode = Api.normalizeTrack({
      played_at: "2026-08-11T10:00:00Z",
      item: {
        id: "episode-id",
        uri: "spotify:episode:episode-id",
        type: "episode",
        name: "Episode one",
        duration_ms: 3600000,
        resume_point: { resume_position_ms: 42000, fully_played: false },
        show: {
          id: "show-id",
          uri: "spotify:show:show-id",
          type: "show",
          name: "A show",
          images: [{ url: "show-art", width: 128 }]
        }
      }
    }, 96)

    compare(episode.type, "episode")
    compare(episode.subtitle, "A show")
    compare(episode.parentContext.type, "show")
    compare(episode.resumeMs, 42000)
    compare(episode.fullyPlayed, false)
    compare(episode.playedAt, "2026-08-11T10:00:00Z")
  }

  function test_searchGroups_normalizeEverySupportedType() {
    var groups = Api.searchGroups({
      tracks: { items: [{ id: "t", uri: "spotify:track:t", type: "track", name: "Track" }], total: 1 },
      artists: { items: [{ id: "a", uri: "spotify:artist:a", type: "artist", name: "Artist" }], total: 1 },
      albums: { items: [{ id: "b", uri: "spotify:album:b", type: "album", name: "Album" }], total: 1 },
      playlists: { items: [{ id: "p", uri: "spotify:playlist:p", type: "playlist", name: "Playlist" }], total: 1 },
      shows: { items: [{ id: "s", uri: "spotify:show:s", type: "show", name: "Show" }], total: 1 },
      episodes: { items: [{ id: "e", uri: "spotify:episode:e", type: "episode", name: "Episode" }], total: 1 },
      audiobooks: { items: [{ id: "book", uri: "spotify:audiobook:book", type: "audiobook", name: "Book" }], total: 1 }
    })

    compare(groups.track.items[0].type, "track")
    compare(groups.artist.items[0].type, "artist")
    compare(groups.album.items[0].type, "album")
    compare(groups.playlist.items[0].type, "playlist")
    compare(groups.show.items[0].type, "show")
    compare(groups.episode.items[0].type, "episode")
    compare(groups.audiobook.items[0].type, "audiobook")
  }

  function test_normalizeContext_labelsAlbumsAndEps() {
    var album = Api.normalizeContext({
      id: "album", uri: "spotify:album:album", type: "album",
      album_type: "album", name: "Full length", release_date: "2025-04-10",
      total_tracks: 12, artists: [{ name: "Artist" }]
    })
    var ep = Api.normalizeContext({
      id: "ep", uri: "spotify:album:ep", type: "album",
      album_type: "single", name: "Short release", release_date: "2026",
      total_tracks: 5, artists: [{ name: "Artist" }]
    })

    compare(album.subtitle, "Artist · Album · 2025")
    compare(album.releaseType, "album")
    compare(ep.subtitle, "Artist · EP / Single · 2026")
  }

  function test_playlistItemUris_keepsOrderAndDuplicates() {
    var uris = Api.playlistItemUris([
      { type: "track", uri: "spotify:track:one" },
      { type: "track", uri: "spotify:track:one" },
      { type: "album", uri: "spotify:album:nope" },
      { type: "episode", uri: "spotify:episode:two" },
      { type: "track", uri: "" }
    ])
    compare(JSON.stringify(uris), JSON.stringify([
      "spotify:track:one", "spotify:track:one", "spotify:episode:two"
    ]))
  }

  function test_mergeSearchGroups_keepsUnchangedCategories() {
    var first = Api.searchGroups({
      tracks: { items: [{ id: "one", uri: "spotify:track:one", type: "track", name: "One" }], total: 2 },
      artists: { items: [{ id: "artist", uri: "spotify:artist:artist", type: "artist", name: "Artist" }], total: 1 }
    })
    var more = Api.searchGroups({
      tracks: { items: [{ id: "two", uri: "spotify:track:two", type: "track", name: "Two" }], total: 2 }
    })
    var merged = Api.mergeSearchGroups(first, more)

    compare(merged.track.items.length, 2)
    compare(merged.artist.items.length, 1)
  }

  function test_filteredSorted_filtersAndSortsWithoutMutatingSource() {
    var source = [
      { name: "Zulu", subtitle: "Someone", addedAt: "2026-01-01" },
      { name: "Alpha", subtitle: "Target artist", addedAt: "2026-08-01" }
    ]
    var filtered = Api.filteredSorted(source, "target", "name")
    compare(filtered.length, 1)
    compare(filtered[0].name, "Alpha")

    var sorted = Api.filteredSorted(source, "", "date")
    compare(sorted[0].name, "Alpha")
    compare(source[0].name, "Zulu")
  }

  function test_touchHistory_deduplicatesAndCaps() {
    var history = Api.touchHistory(["old", "same", "older"], " same ", 3)
    compare(JSON.stringify(history), JSON.stringify(["same", "old", "older"]))
    history = Api.touchHistory(history, "new", 3)
    compare(JSON.stringify(history), JSON.stringify(["new", "same", "old"]))
  }

  function test_normalizePage_filtersMalformedRowsAndNextHost() {
    var page = Api.normalizePage({
      items: [
        { type: "track", id: "one", uri: "spotify:track:one", name: "One" },
        { type: "unsupported", id: "bad" }
      ],
      next: Api.API_BASE + "/me/tracks?offset=1",
      previous: "https://attacker.example/steal",
      total: 2
    }, function(value) { return Api.normalizeTrack(value, 64) })

    compare(page.items.length, 1)
    compare(page.items[0].id, "one")
    compare(page.next, Api.API_BASE + "/me/tracks?offset=1")
    compare(page.previous, "")
    compare(page.total, 2)
  }

  function test_playbackBodies() {
    compare(JSON.stringify(Api.playbackBody({
      kind: "context", type: "playlist", uri: "spotify:playlist:abc"
    })), JSON.stringify({ context_uri: "spotify:playlist:abc" }))
    compare(JSON.stringify(Api.playbackBody({
      kind: "item", type: "track", uri: "spotify:track:def"
    })), JSON.stringify({ uris: ["spotify:track:def"] }))

    var rows = [
      { kind: "item", uri: "spotify:track:a" },
      { kind: "item", uri: "spotify:track:b" },
      { kind: "context", uri: "spotify:album:ignored" },
      { kind: "item", uri: "spotify:track:c" }
    ]
    compare(JSON.stringify(Api.playbackBody(rows[1], rows, "")), JSON.stringify({
      uris: ["spotify:track:b", "spotify:track:c", "spotify:track:a"]
    }))
    compare(JSON.stringify(Api.playbackBody(rows[1], rows, "spotify:playlist:list")),
      JSON.stringify({
        context_uri: "spotify:playlist:list",
        offset: { uri: "spotify:track:b" }
      }))
    compare(Api.playbackBody(null), null)
    compare(Api.playbackBody({
      kind: "context", type: "show", uri: "spotify:show:podcast"
    }), null)
    compare(JSON.stringify(Api.playbackBody({
      kind: "item", type: "episode", uri: "spotify:episode:one", resumeMs: 9000
    }, [], "spotify:show:podcast")), JSON.stringify({
      uris: ["spotify:episode:one"], position_ms: 9000
    }))
  }

  function test_playbackPreservesActiveDeviceAndFallsBackToLocal() {
    var external = { id: "desktop", local: false, active: true, restricted: false }
    var local = { id: "omarchy", local: true, active: false, restricted: false }
    var devices = [external, local]

    compare(Api.preferredPlaybackDevice(devices, "", false).id, "desktop")
    compare(Api.preferredPlaybackDevice(devices, "omarchy", false).id, "desktop")
    compare(Api.preferredPlaybackDevice(devices, "desktop", true).id, "desktop")

    external.active = false
    compare(Api.preferredPlaybackDevice(devices, "", false).id, "omarchy")
  }

  function test_currentPlaybackDeviceWorksBeforeDeviceListLoads() {
    var current = {
      id: "phone", name: "Phone", type: "Smartphone",
      local: false, active: true, restricted: false
    }

    compare(Api.preferredPlaybackDevice([], "", false, current).id, "phone")
  }

  function test_explicitDeviceOverridesCurrentPlaybackDevice() {
    var selected = { id: "speaker", local: false, active: false, restricted: false }
    var current = { id: "phone", local: false, active: true, restricted: false }

    compare(Api.preferredPlaybackDevice([selected], "speaker", true, current).id,
      "speaker")
  }

  function test_activePlaybackTargetOmitsDeviceId() {
    var active = { id: "phone", active: true }
    var fallback = { id: "omarchy", active: false }

    compare(Api.playbackTargetDeviceId(active, false), "")
    compare(Api.playbackTargetDeviceId(active, true), "phone")
    compare(Api.playbackTargetDeviceId(fallback, false), "omarchy")
    compare(Api.playbackTargetDeviceId(null, false), "")
  }

  function test_restrictedActiveDeviceDoesNotSilentlyFallBackToLocal() {
    var speaker = {
      id: "speaker", local: false, active: true, restricted: true
    }
    var local = {
      id: "omarchy", local: true, active: false, restricted: false
    }

    compare(Api.preferredPlaybackDevice([speaker, local], "", false).id,
      "speaker")
    compare(Api.playbackTargetDeviceId(speaker, false), "")
  }

  function test_unavailableExplicitDeviceFallsBackToLocal() {
    var local = { id: "omarchy", local: true, restricted: false }
    compare(Api.preferredPlaybackDevice([local], "gone", true).id, "omarchy")
    compare(Api.preferredPlaybackDevice([], "gone", true), null)
  }

  function test_localPlaybackDevice_survivesAConfiguredRename() {
    verify(Api.isLocalPlaybackDevice({ id: "local", name: "Old desk" },
      "New desk", "Old desk", ""))
    verify(Api.isLocalPlaybackDevice({ id: "local", name: "Unexpected API label" },
      "New desk", "", "local"))
    verify(!Api.isLocalPlaybackDevice({ id: "speaker", name: "Kitchen" },
      "New desk", "Old desk", "local"))
  }

  function test_playbackDeviceMatch_fallsBackToNameWhenCurrentIdIsMissing() {
    verify(Api.playbackDevicesMatch({ id: "", name: "Work", type: "Speaker" },
      { id: "sonos-id", name: "work", type: "speaker" }))
    verify(!Api.playbackDevicesMatch({ id: "api-id", name: "Work", type: "Speaker" },
      { id: "different-id", name: "Work", type: "Speaker" }))
    verify(!Api.playbackDevicesMatch({ id: "", name: "Work", type: "Speaker" },
      { id: "sonos-id", name: "Work", type: "Computer" }))
  }

  function test_playbackDeviceDisplayName_prefersMatchedLocalAlias() {
    var deviceId = "0123456789abcdef0123456789abcdef01234567"
    var current = { id: deviceId, name: deviceId, type: "Speaker" }
    var receivers = [{
      id: deviceId, name: "Living room soundbar", type: "Speaker",
      brand: "JBL", model: "BAR_800"
    }]

    verify(Api.spotifyDeviceNameNeedsDiscovery(current))
    compare(Api.playbackDeviceDisplayName(current, receivers), "Living room soundbar")
    compare(Api.playbackDeviceDisplayName(current, []), deviceId)
    verify(!Api.spotifyDeviceNameNeedsDiscovery({
      id: deviceId, name: "Living room", type: "Speaker"
    }))
  }

  function test_spotifyConnectTokenType_preservesSupportedReceiverFlows() {
    compare(Api.spotifyConnectTokenType("accesstoken"), "accesstoken")
    compare(Api.spotifyConnectTokenType("authorization_code"), "authorization_code")
    compare(Api.spotifyConnectTokenType("default"), "default")
    compare(Api.spotifyConnectTokenType("unexpected"), "default")
  }

  function test_normalizePlaybackState_keepsRemoteTrackAndNullableDeviceId() {
    var state = Api.normalizePlaybackState({
      is_playing: true,
      progress_ms: 42000,
      repeat_state: "context",
      shuffle_state: true,
      device: {
        id: null, name: "Work", type: "Speaker", is_active: true,
        is_restricted: true, volume_percent: 33, supports_volume: true
      },
      item: {
        id: "track", uri: "spotify:track:track", type: "track",
        name: "A song", duration_ms: 180000,
        artists: [{ name: "An artist" }], album: { name: "An album" }
      }
    }, 192)

    verify(state !== null)
    compare(state.device.id, "")
    compare(state.device.name, "Work")
    compare(state.device.restricted, true)
    compare(state.device.volumePercent, 33)
    compare(state.item.name, "A song")
    compare(state.item.subtitle, "An artist")
    compare(state.progressSeconds, 42)
    compare(state.repeatMode, "context")
    compare(state.shuffle, true)
  }

  function test_normalizePlaybackState_preservesUnknownRemoteVolume() {
    var state = Api.normalizePlaybackState({
      device: {
        id: "phone", name: "Phone", type: "Smartphone", is_active: true,
        is_restricted: false, volume_percent: null, supports_volume: true
      }
    }, 192)

    verify(state !== null)
    compare(state.device.volumePercent, null)
    compare(state.device.supportsVolume, true)
  }

  function test_normalizePlaybackState_rejectsEmptyPlaybackResponse() {
    compare(Api.normalizePlaybackState(null, 192), null)
    compare(Api.normalizePlaybackState({}, 192), null)
    compare(Api.normalizePlaybackState([], 192), null)
  }

  function test_mergeUnique_preservesOrder() {
    var merged = Api.mergeUnique([
      { uri: "spotify:track:a" },
      { uri: "spotify:track:b" }
    ], [
      { uri: "spotify:track:b" },
      { uri: "spotify:track:c" }
    ])
    compare(merged.length, 3)
    compare(merged[0].uri, "spotify:track:a")
    compare(merged[2].uri, "spotify:track:c")
  }

  function test_redact_coversHeadersFormsUrlsAndJson() {
    var raw = [
      "Authorization: Bearer access-value",
      "refresh_token=refresh-value&code=authorization-value",
      "?code_verifier=verifier-value&client_secret=secret-value",
      "{\"access_token\":\"json-token\",\"password\":\"nope\"}"
    ].join("\n")
    var safe = Api.redact(raw)

    verify(safe.indexOf("access-value") === -1)
    verify(safe.indexOf("refresh-value") === -1)
    verify(safe.indexOf("authorization-value") === -1)
    verify(safe.indexOf("verifier-value") === -1)
    verify(safe.indexOf("secret-value") === -1)
    verify(safe.indexOf("json-token") === -1)
    verify(safe.indexOf("\"nope\"") === -1)
    verify(safe.indexOf("<redacted>") >= 0)
  }

  function test_clockFormatting() {
    compare(Api.millisecondsToClock(0), "0:00")
    compare(Api.millisecondsToClock(61000), "1:01")
    compare(Api.millisecondsToClock(-100), "0:00")
  }

  function test_quotaErrorIncludesMachineReason() {
    compare(Api.responseError(429, {
      error: { status: 429, message: "Too many requests", reason: "QUOTA_EXCEEDED" }
    }, ""), "Too many requests (QUOTA_EXCEEDED)")
  }
}
