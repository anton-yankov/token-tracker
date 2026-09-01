defmodule TokenTrackerWeb.Router do
  use Phoenix.Router

  pipeline :api do
    plug(TokenTrackerWeb.QueryParams)
    plug(:accepts, ["json"])
  end

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  scope "/api", TokenTrackerWeb do
    pipe_through(:api)
    get("/healthz", HealthController, :show)
    get("/report", ReportController, :show)
    get("/system", SystemController, :show)
    get("/quota", QuotaController, :show)
    get("/tracking", TrackingController, :index)
    post("/tracking/start", TrackingController, :start)
    post("/tracking/stop", TrackingController, :stop)
    delete("/tracking/:id", TrackingController, :delete)
    get("/fx", FxController, :show)
    match(:*, "/*path", NotFoundController, :show)
  end

  scope "/", TokenTrackerWeb do
    pipe_through(:browser)
    get("/*path", SpaController, :show)
  end
end
