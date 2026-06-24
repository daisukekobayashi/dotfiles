defmodule DapE2E do
  def tripwire do
    value = 41
    value + 1
  end

  def run do
    IO.puts("dap-e2e-result=#{tripwire()}")
  end
end
