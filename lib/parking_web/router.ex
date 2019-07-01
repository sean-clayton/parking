defmodule ParkingWeb.Router do
  use ParkingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", ParkingWeb do
    pipe_through :api
  end
end
