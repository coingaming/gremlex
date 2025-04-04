defmodule Gremlex.MixProject do
  use Mix.Project

  def project do
    [
      app: :gremlex,
      version: "0.3.2",
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      source_url: "https://github.com/coingaming/gremlex",
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      docs: [
        # The main page in the docs
        main: "Gremlex",
        logo: "logo.png",
        extras: ["README.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Gremlex.Application, []}
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:poolboy, "~> 1.5.1"},
      {:castore, "~> 1.0"},
      {:mint_web_socket, "~> 1.0"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.0", only: :test}
    ]
  end

  defp description do
    "An Elixir client for Gremlin (Apache TinkerPop™), a simple to use library for creating Gremlin queries."
  end

  defp package() do
    [
      name: "gremlex",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/coingaming/gremlex"}
    ]
  end
end
