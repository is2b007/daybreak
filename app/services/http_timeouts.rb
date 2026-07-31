# Shared Net::HTTP entry points for the Basecamp and HEY clients.
#
# Net::HTTP defaults to a 60-second open *and* read timeout. Daybreak calls these
# APIs from inside the request cycle (manual sync, the avatar proxy, focus-view
# comment fetches), so a hung upstream would pin a Puma thread for a full minute
# — enough to stall the whole app on the default single-worker/3-thread setup.
# Every outbound call goes through here so the timeouts can't be forgotten.
module HttpTimeouts
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20

  def http_start(uri, &block)
    Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT,
      write_timeout: READ_TIMEOUT,
      &block
    )
  end

  # Replacement for Net::HTTP.post_form, which accepts no timeout options.
  def http_post_form(uri, params)
    req = Net::HTTP::Post.new(uri)
    req.form_data = params
    http_start(uri) { |http| http.request(req) }
  end
end
