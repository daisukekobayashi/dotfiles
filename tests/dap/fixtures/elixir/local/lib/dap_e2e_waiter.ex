defmodule DapE2E.Waiter do
  def wait(path \\ "dap_e2e.trigger") do
    if File.exists?(path) do
      DapE2E.loop()
    else
      Process.sleep(100)
      wait(path)
    end
  end
end
