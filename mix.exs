defmodule Crux.Extensions.MixProject do
  use Mix.Project

  @vsn "0.1.0-dev"
  @name :crux_extensions

  def project do
    [
      app: @name,
      version: @vsn,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      source_url: "https://github.com/SpaceEEC/#{@name}/",
      homepage_url: "https://github.com/SpaceEEC/#{@name}/"
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:crux_base, git: "https://github.com/spaceeec/crux_base"},
      {:crux_rest, "~> 0.2.0"},
      {:gen_stage, ">= 0.0.0"},
      {:ex_doc,
       git: "https://github.com/spaceeec/ex_doc",
       branch: "feat/umbrella",
       only: :dev,
       runtime: false}
    ]
  end
end
