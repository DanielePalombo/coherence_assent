defmodule CoherenceAssent.Strategy.FacebookTest do
  use CoherenceAssent.Test.ConnCase

  import OAuth2.TestHelpers
  alias CoherenceAssent.Strategy.Facebook

  @access_token "access_token"

  setup %{conn: conn} do
    conn = session_conn(conn)

    bypass = Bypass.open
    config = [site: bypass_server(bypass)]

    {:ok, conn: conn, config: config, bypass: bypass}
  end

  test "authorize_url/2", %{conn: conn, config: config} do
    assert {:ok, %{conn: _conn, url: url}} = Facebook.authorize_url(conn, config)
    assert url =~ "https://www.facebook.com/v2.12/dialog/oauth?client_id="
  end

  describe "callback/2" do
    setup %{conn: conn, config: config, bypass: bypass} do
      params = %{"code" => "test", "redirect_uri" => "test", "state" => "test"}
      conn = Plug.Conn.put_session(conn, "coherence_assent.state", "test")

      {:ok, conn: conn, config: config, params: params, bypass: bypass}
    end

    test "normalizes data", %{conn: conn, config: config, params: params, bypass: bypass} do
      Bypass.expect_once bypass, "POST", "/oauth/access_token", fn conn ->
        assert {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert body =~ "scope=email"

        send_resp(conn, 200, Poison.encode!(%{"access_token" => @access_token}))
      end

      Bypass.expect_once bypass, "GET", "/me", fn conn ->
        assert_access_token_in_header conn, @access_token

        conn = Plug.Conn.fetch_query_params(conn)

        assert conn.params["fields"] == "name,email"
        assert conn.params["appsecret_proof"] == Base.encode16(:crypto.hmac(:sha256, "", @access_token), case: :lower)

        user = %{name: "Dan Schultzer",
                 email: "foo@example.com",
                 id: "1"}
        Plug.Conn.resp(conn, 200, Poison.encode!(user))
      end

      expected = %{"email" => "foo@example.com",
                   "image" => "http://localhost:#{bypass.port}/1/picture",
                   "name" => "Dan Schultzer",
                   "uid" => "1",
                   "urls" => %{}}

     {:ok, %{user: user}} = Facebook.callback(conn, config, params)
      assert expected == user
    end
  end
end
