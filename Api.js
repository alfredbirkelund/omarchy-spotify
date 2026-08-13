.pragma library

var API_BASE = "https://api.spotify.com/v1"
var TOKEN_URL = "https://accounts.spotify.com/api/token"
var AUTH_URL = "https://accounts.spotify.com/authorize"

// Deliberately omit profile and email scopes. The remaining scopes correspond
// directly to visible library, history, playlist, and playback controls.
var SCOPES = [
  "user-library-read",
  "user-library-modify",
  "user-follow-read",
  "user-follow-modify",
  "user-read-recently-played",
  "user-read-playback-position",
  "user-top-read",
  "playlist-read-private",
  "playlist-read-collaborative",
  "playlist-modify-private",
  "playlist-modify-public",
  "user-read-playback-state",
  "user-modify-playback-state"
]

var SEARCH_TYPES = ["track", "artist", "album", "playlist", "show", "episode", "audiobook"]
var DISCOVERY_SEARCHES = [
  "Discover Weekly",
  "Release Radar",
  "daylist",
  "Daily Mix",
  "New Music Friday",
  "Fresh Finds"
]

function encode(value) {
  return encodeURIComponent(String(value === undefined || value === null ? "" : value))
}

function queryString(values) {
  if (!values) return ""
  var pairs = []
  var keys = Object.keys(values).sort()
  for (var i = 0; i < keys.length; i++) {
    var key = keys[i]
    var value = values[key]
    if (value === undefined || value === null || value === "") continue
    if (Array.isArray(value)) value = value.join(",")
    pairs.push(encode(key) + "=" + encode(value))
  }
  return pairs.join("&")
}

function appendQuery(path, values) {
  var query = queryString(values)
  if (!query) return String(path || "")
  return String(path || "") + (String(path || "").indexOf("?") >= 0 ? "&" : "?") + query
}

function formBody(values) {
  return queryString(values)
}

function parseJson(text, fallback) {
  try {
    var parsed = JSON.parse(String(text || ""))
    return parsed === null ? fallback : parsed
  } catch (e) {
    return fallback
  }
}

function safeApiUrl(path) {
  var value = String(path || "")
  if (value.charAt(0) === "/") return API_BASE + value
  if (value === API_BASE || value.indexOf(API_BASE + "/") === 0) return value
  return ""
}

function redact(value) {
  var text = String(value || "")
  text = text.replace(/(authorization\s*:\s*bearer\s+)[^\s]+/ig, "$1<redacted>")
  text = text.replace(/(^|[?&\s])((?:code|access_token|refresh_token|code_verifier|client_secret|password)=)[^&#\s]+/ig, "$1$2<redacted>")
  text = text.replace(/("(?:access_token|refresh_token|code|code_verifier|client_secret|password)"\s*:\s*")[^"]+/ig, "$1<redacted>")
  return text
}

function responseError(status, payload, fallback) {
  var message = ""
  if (payload && typeof payload === "object") {
    if (typeof payload.error === "object" && payload.error) {
      message = payload.error.message || payload.error.status || ""
      if (payload.error.reason && String(payload.error.reason) !== String(message))
        message += (message ? " (" : "") + String(payload.error.reason) + (message ? ")" : "")
    }
    else if (typeof payload.error === "string")
      message = payload.error_description || payload.error
    else
      message = payload.message || ""
  }
  if (!message) message = fallback || "Spotify could not complete this request"
  return redact(message)
}

// Playback defaults to this app's local spotifyd device. An external device is
// considered only when the user selected it explicitly in the Devices view;
// merely being active in another Spotify client must never steal a play click.
function preferredPlaybackDevice(devices, selectedId, explicitSelection) {
  var values = Array.isArray(devices) ? devices : []
  var key = String(selectedId || "")
  if (explicitSelection && key) {
    for (var i = 0; i < values.length; i++)
      if (String(values[i].id || "") === key && values[i].restricted !== true)
        return values[i]
  }
  for (var j = 0; j < values.length; j++)
    if (values[j].local === true && values[j].restricted !== true && values[j].id)
      return values[j]
  return null
}

function isLocalPlaybackDevice(device, configuredName, runtimeName, knownId) {
  var item = device || {}
  var id = String(item.id || "")
  var rememberedId = String(knownId || "")
  if (id && rememberedId && id === rememberedId) return true
  var name = String(item.sourceName || item.name || "")
  var configured = String(configuredName || "")
  var runtime = String(runtimeName || "")
  return !!name && (name === configured || (!!runtime && name === runtime))
}

// Spotify may expose an active hardware player through /me/player while
// omitting it from /me/player/devices (Sonos is a common example). Device ids
// are authoritative when both endpoints provide one; otherwise fall back to
// the user-visible name and device type.
function playbackDevicesMatch(left, right) {
  var first = left || {}
  var second = right || {}
  var firstId = String(first.id || "")
  var secondId = String(second.id || "")
  if (firstId && secondId) return firstId === secondId
  var firstName = String(first.name || first.sourceName || "").trim().toLowerCase()
  var secondName = String(second.name || second.sourceName || "").trim().toLowerCase()
  if (!firstName || firstName !== secondName) return false
  var firstType = String(first.type || "").trim().toLowerCase()
  var secondType = String(second.type || "").trim().toLowerCase()
  return !firstType || !secondType || firstType === secondType
}

function normalizePlaybackState(value, imageWidth) {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null
  var source = value
  var rawDevice = source.device || null
  var device = rawDevice && typeof rawDevice === "object" ? {
    id: String(rawDevice.id || ""),
    name: String(rawDevice.name || "Spotify device"),
    type: String(rawDevice.type || "unknown"),
    active: rawDevice.is_active === true,
    restricted: rawDevice.is_restricted === true,
    volumePercent: Math.max(0, Math.min(100,
      Number(rawDevice.volume_percent) || 0)),
    supportsVolume: rawDevice.supports_volume === true
  } : null
  var item = source.item && typeof source.item === "object"
    ? normalizeTrack(source.item, imageWidth || 192) : null
  if (!device && !item) return null
  return {
    device: device,
    item: item,
    playing: source.is_playing === true,
    progressSeconds: Math.max(0, Number(source.progress_ms) || 0) / 1000,
    receivedAt: Date.now(),
    repeatMode: ["off", "track", "context"].indexOf(String(source.repeat_state)) >= 0
      ? String(source.repeat_state) : "off",
    shuffle: source.shuffle_state === true,
    contextUri: source.context && source.context.uri
      ? String(source.context.uri) : "",
    disallows: source.actions && source.actions.disallows
      && typeof source.actions.disallows === "object"
      ? source.actions.disallows : ({})
  }
}

function imageFor(images, targetWidth) {
  if (!Array.isArray(images) || images.length === 0) return ""
  var target = Math.max(1, Number(targetWidth) || 128)
  var best = null
  var bestScore = Number.MAX_VALUE
  for (var i = 0; i < images.length; i++) {
    var image = images[i]
    if (!image || !image.url) continue
    var width = Number(image.width) || target
    // Prefer the smallest image that is still large enough. Undersized images
    // get a larger penalty so artwork is not visibly upscaled.
    var score = width >= target ? width - target : (target - width) * 4
    if (score < bestScore) {
      best = image
      bestScore = score
    }
  }
  return best ? String(best.url) : ""
}

function artistNames(artists) {
  if (!Array.isArray(artists)) return ""
  var names = []
  for (var i = 0; i < artists.length; i++)
    if (artists[i] && artists[i].name) names.push(String(artists[i].name))
  return names.join(", ")
}

function catalogSearchText(artistName, term) {
  function clean(value) {
    return String(value || "").replace(/["\\]/g, " ").replace(/\s+/g, " ").trim()
  }
  var artist = clean(artistName)
  var query = clean(term)
  var filter = artist ? "artist:\"" + artist + "\"" : ""
  return query && filter ? query + " " + filter : (query || filter)
}

function tracksForArtist(items, artist) {
  var rows = Array.isArray(items) ? items : []
  var target = artist || {}
  var targetId = String(target.id || "")
  var targetName = String(target.name || "").toLowerCase()
  var result = []
  for (var i = 0; i < rows.length; i++) {
    var track = rows[i]
    if (!track || track.type !== "track" || !Array.isArray(track.artists)) continue
    var matched = false
    for (var a = 0; a < track.artists.length; a++) {
      var performer = track.artists[a] || {}
      if ((targetId && String(performer.id || "") === targetId)
          || (!targetId && targetName
            && String(performer.name || "").toLowerCase() === targetName)) {
        matched = true
        break
      }
    }
    if (matched) result.push(track)
  }
  return result
}

function comparablePlaylistTitle(value) {
  return String(value || "").toLowerCase()
    .replace(/[’‘`]/g, "'")
    .replace(/[-–—_:.,!?()[\]{}"'\/\\]+/g, " ")
    .replace(/\s+/g, " ").trim()
}

function findThisIsPlaylist(items, artistName) {
  var expected = comparablePlaylistTitle("This Is " + String(artistName || ""))
  if (!expected || !String(artistName || "").trim()) return null
  var rows = Array.isArray(items) ? items : []
  var best = null
  var bestScore = -1
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    if (!item || item.type !== "playlist" || !item.id
        || comparablePlaylistTitle(item.name) !== expected) continue
    var ownerId = String(item.ownerId || "").toLowerCase()
    var ownerName = String(item.ownerName || "").toLowerCase()
    var score = ownerId === "spotify" || ownerName === "spotify" ? 2 : 0
    if (item.imageUrl) score++
    if (score > bestScore) {
      best = item
      bestScore = score
    }
  }
  return best
}

function trackRadioPlaylists(items, trackName) {
  var expected = comparablePlaylistTitle(String(trackName || "") + " Radio")
  if (!expected || !String(trackName || "").trim()) return []
  var rows = Array.isArray(items) ? items : []
  var result = []
  var seen = ({})
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    if (!item || item.type !== "playlist" || !item.id || !item.uri
        || comparablePlaylistTitle(item.name) !== expected) continue
    var ownerId = String(item.ownerId || "").toLowerCase()
    var ownerName = String(item.ownerName || "").toLowerCase()
    var key = String(item.uri || item.id)
    if ((ownerId !== "spotify" && ownerName !== "spotify") || seen[key]) continue
    seen[key] = true
    result.push(item)
  }
  return result
}

function radioSeedMatches(candidate, seed) {
  var item = candidate || {}
  var target = seed || {}
  var itemId = String(item.id || "")
  var targetId = String(target.id || "")
  var itemUri = String(item.uri || "")
  var targetUri = String(target.uri || "")
  if ((itemId && targetId && itemId === targetId)
      || (itemUri && targetUri && itemUri === targetUri)) return true
  if (comparablePlaylistTitle(item.name) !== comparablePlaylistTitle(target.name))
    return false

  var itemArtists = Array.isArray(item.artists) ? item.artists : []
  var targetArtists = Array.isArray(target.artists) ? target.artists : []
  for (var i = 0; i < itemArtists.length; i++) {
    var itemArtist = itemArtists[i] || {}
    var itemArtistId = String(itemArtist.id || "")
    var itemArtistName = comparablePlaylistTitle(itemArtist.name)
    for (var j = 0; j < targetArtists.length; j++) {
      var targetArtist = targetArtists[j] || {}
      var targetArtistId = String(targetArtist.id || "")
      var targetArtistName = comparablePlaylistTitle(targetArtist.name)
      if ((itemArtistId && targetArtistId && itemArtistId === targetArtistId)
          || (itemArtistName && targetArtistName && itemArtistName === targetArtistName))
        return true
    }
  }
  return false
}

function discoveryPlaylistRank(item) {
  if (!item || item.type !== "playlist" || !item.id) return -1
  var ownerId = String(item.ownerId || "").toLowerCase()
  var ownerName = String(item.ownerName || "").toLowerCase()
  if (ownerId !== "spotify" && ownerName !== "spotify") return -1
  var title = comparablePlaylistTitle(item.name)
  if (title === "discover weekly") return 0
  if (title === "release radar") return 1
  if (title === "daylist") return 2
  if (title === "daily mix") return 9
  var daily = title.match(/^daily mix ([0-9]+)$/)
  if (daily) return 10 + Math.max(0, Number(daily[1]) || 0)
  if (title === "new music friday") return 30
  if (title.indexOf("new music friday ") === 0) return 31
  if (title === "fresh finds") return 40
  if (title.indexOf("fresh finds ") === 0) return 41
  return -1
}

function discoveryPlaylists(items, maximum) {
  var rows = Array.isArray(items) ? items : []
  var ranked = []
  var seen = ({})
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i]
    var rank = discoveryPlaylistRank(item)
    var key = String((item && (item.uri || item.id)) || "")
    if (rank < 0 || !key || seen[key]) continue
    seen[key] = true
    ranked.push({ item: item, rank: rank, index: i })
  }
  ranked.sort(function(left, right) {
    if (left.rank !== right.rank) return left.rank - right.rank
    var leftName = String(left.item.name || "").toLowerCase()
    var rightName = String(right.item.name || "").toLowerCase()
    if (leftName < rightName) return -1
    if (leftName > rightName) return 1
    return left.index - right.index
  })
  var limit = Math.max(1, Number(maximum) || 24)
  var result = []
  for (var j = 0; j < ranked.length && result.length < limit; j++)
    result.push(ranked[j].item)
  return result
}

function albumKind(item) {
  var source = item || {}
  var type = String(source.album_type || source.album_group || "").toLowerCase()
  if (type === "single") return Number(source.total_tracks) > 1 ? "EP / Single" : "Single"
  if (type === "compilation") return "Compilation"
  return type === "album" ? "Album" : "Release"
}

function playlistItemUris(items) {
  var rows = Array.isArray(items) ? items : []
  var uris = []
  for (var i = 0; i < rows.length; i++) {
    var item = rows[i] || {}
    if (item.uri && ["track", "episode"].indexOf(String(item.type || "")) >= 0)
      uris.push(String(item.uri))
  }
  return uris
}

function normalizedArtists(artists, imageWidth) {
  if (!Array.isArray(artists)) return []
  var rows = []
  for (var i = 0; i < artists.length; i++) {
    var source = artists[i] || {}
    // Spotify's simplified artist object normally carries `type`, but some
    // playlist and cached payloads omit it. Artist links should still work.
    var artist = normalizeContext({
      id: source.id,
      uri: source.uri,
      type: source.type || "artist",
      name: source.name,
      images: source.images,
      external_urls: source.external_urls
    }, imageWidth)
    if (artist && artist.type === "artist") rows.push(artist)
  }
  return rows
}

function normalizeTrack(value, imageWidth, parentContext) {
  var source = value || {}
  var item = source.item || source.track || source.episode || source.chapter || source
  if (!item || typeof item !== "object") return null
  var album = item.album || {}
  var type = String(item.type || "track")
  if (["track", "episode", "chapter"].indexOf(type) === -1) return null
  var subtitle = type === "episode"
    ? String((item.show && item.show.name) || item.description || "Podcast")
    : (type === "chapter"
      ? String((item.audiobook && item.audiobook.name) || item.description || "Audiobook")
      : artistNames(item.artists))
  var images = type === "track" ? album.images : item.images
  var albumItem = type === "track" && album && album.name
    ? normalizeContext({
      id: album.id,
      uri: album.uri,
      type: album.type || "album",
      name: album.name,
      artists: album.artists,
      images: album.images,
      release_date: album.release_date,
      total_tracks: album.total_tracks,
      external_urls: album.external_urls
    }, imageWidth || 96) : null
  if (!albumItem && type === "track" && parentContext && parentContext.type === "album")
    albumItem = parentContext
  var parentItem = type === "episode" && item.show
    ? normalizeContext(item.show, imageWidth || 96)
    : (type === "chapter" && item.audiobook
      ? normalizeContext(item.audiobook, imageWidth || 96) : null)
  if (!parentItem && parentContext
      && ((type === "episode" && parentContext.type === "show")
        || (type === "chapter" && parentContext.type === "audiobook")))
    parentItem = parentContext
  if ((type === "episode" || type === "chapter") && parentItem)
    subtitle = String(parentItem.name || subtitle)
  var resume = item.resume_point || {}
  return {
    kind: "item",
    type: type,
    id: String(item.id || ""),
    uri: String(item.uri || ""),
    name: String(item.name || "Untitled"),
    subtitle: subtitle,
    album: String(album.name || (albumItem && albumItem.name) || ""),
    artists: normalizedArtists(item.artists, imageWidth || 96),
    albumItem: albumItem,
    parentContext: parentItem,
    imageUrl: imageFor(images, imageWidth || 96)
      || String((parentContext && parentContext.imageUrl) || ""),
    durationMs: Number(item.duration_ms) || 0,
    trackNumber: Number(item.track_number || item.chapter_number) || 0,
    discNumber: Number(item.disc_number) || 0,
    releaseDate: String(item.release_date || album.release_date || ""),
    addedAt: String(source.added_at || ""),
    playedAt: String(source.played_at || ""),
    resumeMs: Math.max(0, Number(resume.resume_position_ms) || 0),
    fullyPlayed: resume.fully_played === true,
    explicit: item.explicit === true,
    externalUrl: item.external_urls && item.external_urls.spotify
      ? String(item.external_urls.spotify) : ""
  }
}

function normalizeContext(value, imageWidth) {
  var source = value || {}
  var item = source.album || source.artist || source.playlist || source.show
    || source.audiobook || source
  var type = String(item.type || "")
  if (["album", "artist", "playlist", "show", "audiobook"].indexOf(type) === -1) return null
  var subtitle = ""
  if (type === "album") {
    var albumDetails = []
    var albumArtists = artistNames(item.artists)
    if (albumArtists) albumDetails.push(albumArtists)
    albumDetails.push(albumKind(item))
    if (item.release_date) albumDetails.push(String(item.release_date).slice(0, 4))
    subtitle = albumDetails.join(" · ")
  }
  else if (type === "playlist") subtitle = String((item.owner && item.owner.display_name) || "Playlist")
  else if (type === "artist") subtitle = "Artist"
  else if (type === "show") subtitle = String(item.publisher || "Podcast")
  else {
    var authors = []
    var sourceAuthors = Array.isArray(item.authors) ? item.authors : []
    for (var a = 0; a < sourceAuthors.length; a++)
      if (sourceAuthors[a] && sourceAuthors[a].name) authors.push(String(sourceAuthors[a].name))
    subtitle = authors.length ? authors.join(", ") : String(item.publisher || "Audiobook")
  }
  var total = Number(item.total_tracks || item.total_episodes || item.total_chapters) || 0
  if (type === "playlist") total = Number((item.items && item.items.total)
    || (item.tracks && item.tracks.total)) || 0
  return {
    kind: "context",
    type: type,
    id: String(item.id || ""),
    uri: String(item.uri || ""),
    name: String(item.name || "Untitled"),
    subtitle: subtitle,
    description: String(item.description || ""),
    artists: normalizedArtists(item.artists, imageWidth || 128),
    imageUrl: imageFor(item.images, imageWidth || 128),
    total: total,
    releaseType: type === "album" ? String(item.album_type || item.album_group || "") : "",
    releaseDate: String(item.release_date || ""),
    ownerId: String((item.owner && (item.owner.account_id || item.owner.id)) || ""),
    ownerName: String((item.owner && item.owner.display_name) || ""),
    collaborative: item.collaborative === true,
    public: item.public === true,
    snapshotId: String(item.snapshot_id || ""),
    addedAt: String(source.added_at || ""),
    externalUrl: item.external_urls && item.external_urls.spotify
      ? String(item.external_urls.spotify) : ""
  }
}

function normalizePlaylist(value, imageWidth) {
  var normalized = normalizeContext(value, imageWidth)
  if (!normalized || normalized.type !== "playlist") return null
  return normalized
}

function normalizePage(page, mapper) {
  var source = page || {}
  var values = Array.isArray(source.items) ? source.items : []
  var items = []
  for (var i = 0; i < values.length; i++) {
    var mapped = mapper(values[i])
    if (mapped) items.push(mapped)
  }
  return {
    items: items,
    next: safeApiUrl(source.next),
    previous: safeApiUrl(source.previous),
    total: Number(source.total) || items.length
  }
}

function searchRows(payload, imageWidth) {
  var data = payload || {}
  var rows = []
  var i
  var trackItems = data.tracks && Array.isArray(data.tracks.items) ? data.tracks.items : []
  for (i = 0; i < trackItems.length; i++) {
    var track = normalizeTrack(trackItems[i], imageWidth)
    if (track) rows.push(track)
  }
  var groups = [data.albums, data.artists, data.playlists]
  for (var g = 0; g < groups.length; g++) {
    var groupItems = groups[g] && Array.isArray(groups[g].items) ? groups[g].items : []
    for (i = 0; i < groupItems.length; i++) {
      var context = normalizeContext(groupItems[i], imageWidth)
      if (context) rows.push(context)
    }
  }
  return rows
}

function searchTypeKey(type) {
  var value = String(type || "track")
  if (value === "artist") return "artists"
  if (value === "album") return "albums"
  if (value === "playlist") return "playlists"
  if (value === "show") return "shows"
  if (value === "episode") return "episodes"
  if (value === "audiobook") return "audiobooks"
  return "tracks"
}

function normalizeSearchPage(payload, type, imageWidth) {
  var key = searchTypeKey(type)
  var page = payload && payload[key] ? payload[key] : {}
  return normalizePage(page, function(value) {
    return type === "track" || type === "episode"
      ? normalizeTrack(value, imageWidth || 128)
      : normalizeContext(value, imageWidth || 128)
  })
}

function searchGroups(payload, imageWidth) {
  var result = ({})
  for (var i = 0; i < SEARCH_TYPES.length; i++) {
    var type = SEARCH_TYPES[i]
    result[type] = normalizeSearchPage(payload, type, imageWidth || 128)
  }
  return result
}

function mergeSearchGroups(existing, incoming) {
  var result = ({})
  var oldGroups = existing || {}
  var newGroups = incoming || {}
  for (var i = 0; i < SEARCH_TYPES.length; i++) {
    var type = SEARCH_TYPES[i]
    var oldPage = oldGroups[type] || { items: [], next: "", total: 0 }
    if (!newGroups[type]) {
      result[type] = oldPage
      continue
    }
    var nextPage = newGroups[type]
    result[type] = {
      items: mergeUnique(oldPage.items, nextPage.items),
      next: nextPage.next,
      previous: nextPage.previous,
      total: Math.max(Number(oldPage.total) || 0, Number(nextPage.total) || 0)
    }
  }
  return result
}

function normalizeCursorPage(container, mapper) {
  var page = container || {}
  var values = Array.isArray(page.items) ? page.items : []
  var items = []
  for (var i = 0; i < values.length; i++) {
    var mapped = mapper(values[i])
    if (mapped) items.push(mapped)
  }
  return {
    items: items,
    next: safeApiUrl(page.next),
    total: Number(page.total) || items.length,
    after: String((page.cursors && page.cursors.after) || "")
  }
}

function filteredSorted(items, filterText, sortKey) {
  var source = Array.isArray(items) ? items : []
  var term = String(filterText || "").trim().toLowerCase()
  var rows = []
  for (var i = 0; i < source.length; i++) {
    var item = source[i]
    if (!item) continue
    var haystack = [item.name, item.subtitle, item.album, item.description,
      item.releaseDate, item.addedAt].join(" ").toLowerCase()
    if (!term || haystack.indexOf(term) >= 0) rows.push({ item: item, index: i })
  }
  var key = String(sortKey || "default")
  if (key !== "default") {
    rows.sort(function(a, b) {
      var left
      var right
      if (key === "duration") {
        left = Number(a.item.durationMs) || 0
        right = Number(b.item.durationMs) || 0
      } else if (key === "date") {
        left = String(a.item.addedAt || a.item.playedAt || a.item.releaseDate || "")
        right = String(b.item.addedAt || b.item.playedAt || b.item.releaseDate || "")
        if (left < right) return 1
        if (left > right) return -1
        return a.index - b.index
      } else {
        left = String(key === "artist" ? a.item.subtitle
          : (key === "album" ? a.item.album : a.item.name) || "").toLowerCase()
        right = String(key === "artist" ? b.item.subtitle
          : (key === "album" ? b.item.album : b.item.name) || "").toLowerCase()
      }
      if (left < right) return -1
      if (left > right) return 1
      return a.index - b.index
    })
  }
  var result = []
  for (var r = 0; r < rows.length; r++) result.push(rows[r].item)
  return result
}

function parseStringList(value, maximum) {
  var source = value
  if (typeof source === "string") source = parseJson(source, [])
  if (!Array.isArray(source)) return []
  var limit = Math.max(1, Number(maximum) || 50)
  var result = []
  var seen = ({})
  for (var i = 0; i < source.length && result.length < limit; i++) {
    var entry = String(source[i] || "").trim()
    if (!entry || seen[entry]) continue
    seen[entry] = true
    result.push(entry)
  }
  return result
}

function touchHistory(values, term, maximum) {
  var normalized = String(term || "").trim()
  var source = parseStringList(values, maximum || 12)
  if (!normalized) return source
  var result = [normalized]
  for (var i = 0; i < source.length && result.length < (maximum || 12); i++)
    if (source[i].toLowerCase() !== normalized.toLowerCase()) result.push(source[i])
  return result
}

function playbackBody(item, sourceItems, contextUri) {
  if (!item || !item.uri) return null
  // Spotify's playback endpoint accepts only album, artist, and playlist
  // contexts. Podcast episodes and audiobook chapters are sent as items.
  if (["album", "artist", "playlist"].indexOf(item.type) >= 0)
    return { context_uri: String(item.uri) }
  if (item.kind === "context") return null

  var itemUri = String(item.uri)
  var sourceContext = String(contextUri || "")
  if (/^spotify:(album|playlist):/.test(sourceContext))
    return { context_uri: sourceContext, offset: { uri: itemUri } }

  // A lone URI creates a one-track Spotify playback context. That makes Next
  // reach the end immediately, so carry the visible list into playback. Start
  // at the clicked row and wrap once; Spotify accepts at most 100 URIs.
  var values = Array.isArray(sourceItems) ? sourceItems : []
  var start = -1
  for (var i = 0; i < values.length; i++) {
    if (values[i] && String(values[i].uri || "") === itemUri) {
      start = i
      break
    }
  }
  if (start < 0) {
    var single = { uris: [itemUri] }
    if (Number(item.resumeMs) > 0) single.position_ms = Math.floor(Number(item.resumeMs))
    return single
  }

  var uris = []
  var seen = {}
  for (var step = 0; step < values.length && uris.length < 100; step++) {
    var candidate = values[(start + step) % values.length]
    if (!candidate || candidate.kind !== "item") continue
    var uri = String(candidate.uri || "")
    if (!uri || seen[uri]) continue
    seen[uri] = true
    uris.push(uri)
  }
  var body = { uris: uris.length ? uris : [itemUri] }
  if (Number(item.resumeMs) > 0) body.position_ms = Math.floor(Number(item.resumeMs))
  return body
}

function millisecondsToClock(milliseconds) {
  var seconds = Math.max(0, Math.floor((Number(milliseconds) || 0) / 1000))
  var minutes = Math.floor(seconds / 60)
  var remainder = seconds % 60
  return minutes + ":" + (remainder < 10 ? "0" : "") + remainder
}

function mergeUnique(existing, incoming) {
  var result = Array.isArray(existing) ? existing.slice() : []
  var seen = {}
  var i
  for (i = 0; i < result.length; i++) {
    var oldKey = String((result[i] && (result[i].uri || result[i].id)) || "")
    if (oldKey) seen[oldKey] = true
  }
  var values = Array.isArray(incoming) ? incoming : []
  for (i = 0; i < values.length; i++) {
    var key = String((values[i] && (values[i].uri || values[i].id)) || "")
    if (key && seen[key]) continue
    if (key) seen[key] = true
    result.push(values[i])
  }
  return result
}
