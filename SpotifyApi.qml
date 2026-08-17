import QtQuick

import "Api.js" as Api

// Thin authenticated transport. It performs no polling and owns only one
// special request: search, which is cancelled whenever a newer query arrives.
Item {
  id: root

  visible: false
  width: 0
  height: 0

  required property var auth

  property var searchRequest: null
  property int searchSerial: 0

  function abortRequest(handle) {
    if (!handle) return
    handle.aborted = true
    if (handle.xhr && handle.xhr.abort) handle.xhr.abort()
    handle.xhr = null
  }

  function requestError(status, payload, xhr, fallback) {
    var error = Api.responseError(status, payload, fallback)
    if (status === 429 && xhr && xhr.getResponseHeader)
      error += Api.rateLimitSuffix(xhr.getResponseHeader("Retry-After"))
    return error
  }

  function request(method, path, query, body, callback, retried, existingHandle) {
    var handle = existingHandle || { aborted: false, xhr: null }
    var url = Api.safeApiUrl(path)
    if (!url) {
      if (typeof callback === "function")
        callback(0, null, "Something went wrong while contacting Spotify", null)
      return handle
    }
    url = Api.appendQuery(url, query)

    auth.withAccessToken(function(token, tokenError) {
      if (handle.aborted) return
      if (!token) {
        if (typeof callback === "function") callback(0, null, tokenError || "Not logged in", null)
        return
      }
      var xhr = new XMLHttpRequest()
      handle.xhr = xhr
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (handle.xhr === xhr) handle.xhr = null
        if (handle.aborted) return
        var payload = Api.parseJson(xhr.responseText, null)
        if (xhr.status === 401 && retried !== true) {
          auth.invalidateAccessToken()
          root.request(method, path, query, body, callback, true, handle)
          return
        }
        var ok = xhr.status >= 200 && xhr.status < 300
        var error = ok ? "" : root.requestError(xhr.status, payload, xhr,
          "Spotify could not complete this request")
        if (typeof callback === "function") callback(xhr.status, payload, error, xhr)
      }
      xhr.open(String(method || "GET"), url)
      xhr.setRequestHeader("Authorization", "Bearer " + token)
      if (body !== undefined && body !== null) {
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.send(JSON.stringify(body))
      } else {
        xhr.send()
      }
    })
    return handle
  }

  function cancelSearch() {
    searchSerial++
    abortRequest(searchRequest)
    searchRequest = null
  }

  // Search still uses its own serial so a newer query can reject a stale
  // callback created while a token refresh is still in flight.
  function search(query, callback) {
    cancelSearch()
    var serial = searchSerial
    var term = String(query || "").trim()
    if (!term) {
      if (typeof callback === "function") callback(Api.searchGroups({}, 128), "")
      return
    }
    searchRequest = request("GET", "/search", {
      q: term,
      type: Api.SEARCH_TYPES.join(","),
      limit: 10
    }, null, function(status, payload, error) {
      if (serial !== root.searchSerial) return
      if (typeof callback !== "function") return
      if (error) callback(Api.searchGroups({}, 128), error)
      else callback(Api.searchGroups(payload, 128), "")
    })
  }
}
