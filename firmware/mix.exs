defmodule Firmware.MixProject do
  use Mix.Project

  @all_targets [:rpi, :rpi0, :rpi2, :rpi3, :rpi3a, :bbb, :x86_64, :custom_rpi3]

  def project do
    [
      app: :firmware,
      version: "0.1.0",
      elixir: "~> 1.8",
      archives: [nerves_bootstrap: "~> 1.5"],
      start_permanent: Mix.env() == :prod,
      build_embedded: true,
      aliases: [loadconfig: [&bootstrap/1]],
      deps: deps()
    ]
  end

  # Starting nerves_bootstrap adds the required aliases to Mix.Project.config()
  # Aliases are only added if MIX_TARGET is set.
  def bootstrap(args) do
    Application.start(:nerves_bootstrap)
    Mix.Task.run("loadconfig", args)
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {Firmware, []},
      extra_applications: [:logger, :runtime_tools, :audio, :power_control]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nerves, "~> 1.4", runtime: false},
      {:shoehorn, "~> 0.4"},
      {:ring_logger, "~> 0.6"},
      {:toolshed, "~> 0.2"},

      {:nerves_runtime, "~> 0.6", targets: @all_targets},
      {:nerves_init_gadget, "~> 0.4", targets: @all_targets},

      {:power_control, "~> 0.1.0"},
      {:audio, path: "../audio"},
      {:musicbox, path: "../ui"},
      {:rfid, path: "../rfid"},
      {:hid, path: "../hid"},

      {:custom_rpi3, path: "../custom_rpi3", runtime: false, targets: :custom_rpi3},

      {:nerves_system_rpi, "~> 1.6", runtime: false, targets: :rpi},
      {:nerves_system_rpi0, "~> 1.6", runtime: false, targets: :rpi0},
      {:nerves_system_rpi2, "~> 1.6", runtime: false, targets: :rpi2},
      {:nerves_system_rpi3, "~> 1.6", runtime: false, targets: :rpi3},
      {:nerves_system_rpi3a, "~> 1.6", runtime: false, targets: :rpi3a},
      {:nerves_system_bbb, "~> 2.0", runtime: false, targets: :bbb},
      {:nerves_system_x86_64, "~> 1.6", runtime: false, targets: :x86_64}
    ]
  end
end
