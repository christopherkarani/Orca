class Orca < Formula
  desc "Local runtime firewall for AI agents"
  homepage "https://github.com/christopherkarani/Orca"
  version "1.1.0"
  license "Apache-2.0"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-arm64.tar.gz"
      sha256 "b93a7f5fa5d94700f7f990d06e705bfddfcc67bc4b49c0687a630fdab800bc3d"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-darwin-amd64.tar.gz"
      sha256 "fda91b91bff5ef5e5f2c7549b074e7400918c3010d3ec72cf253ce01eff45178"
    end
  end

  on_linux do
    if Hardware::CPU.arm?
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-arm64.tar.gz"
      sha256 "dabd4f89a49c03d7c3c1a9e96bbfeb828b39903d68b666de9c2ae194c78abecf"
    else
      url "https://github.com/christopherkarani/Orca/releases/download/v#{version}/orca-v#{version}-linux-amd64.tar.gz"
      sha256 "ace518c72134b8deee5816819f31781ebf92bfa64a76a20051181a46cf7cf852"
    end
  end

  def install
    bin.install "bin/orca"
    prefix.install "orca-dashboard-ui/dist" => "orca-dashboard-ui/dist"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/orca --version")
  end
end
