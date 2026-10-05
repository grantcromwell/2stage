library ieee;
use ieee.std_logic_1164.all;

entity shadow_top is
  generic (DIM : positive := 24; ADDR_WIDTH : positive := 12; DATA_WIDTH : positive := 32);
  port (
    fclk_clk0 : in std_logic;
    fclk_reset0_n : in std_logic;
    s_axi_awaddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_awvalid : in std_logic; s_axi_awready : out std_logic;
    s_axi_wdata : in std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_wstrb : in std_logic_vector(DATA_WIDTH/8-1 downto 0);
    s_axi_wvalid : in std_logic; s_axi_wready : out std_logic;
    s_axi_bresp : out std_logic_vector(1 downto 0); s_axi_bvalid : out std_logic; s_axi_bready : in std_logic;
    s_axi_araddr : in std_logic_vector(ADDR_WIDTH-1 downto 0);
    s_axi_arvalid : in std_logic; s_axi_arready : out std_logic;
    s_axi_rdata : out std_logic_vector(DATA_WIDTH-1 downto 0);
    s_axi_rresp : out std_logic_vector(1 downto 0); s_axi_rvalid : out std_logic; s_axi_rready : in std_logic;
    irq_f2p : out std_logic
  );
end entity;

architecture rtl of shadow_top is
  attribute X_INTERFACE_INFO : string;
  attribute X_INTERFACE_PARAMETER : string;
  attribute X_INTERFACE_INFO of fclk_clk0 : signal is "xilinx.com:signal:clock:1.0 fclk_clk0 CLK";
  attribute X_INTERFACE_PARAMETER of fclk_clk0 : signal is "ASSOCIATED_BUSIF s_axi, ASSOCIATED_RESET fclk_reset0_n, FREQ_HZ 40000000";
  attribute X_INTERFACE_INFO of fclk_reset0_n : signal is "xilinx.com:signal:reset:1.0 fclk_reset0_n RST";
  attribute X_INTERFACE_PARAMETER of fclk_reset0_n : signal is "POLARITY ACTIVE_LOW";
  attribute X_INTERFACE_INFO of irq_f2p : signal is "xilinx.com:signal:interrupt:1.0 irq_f2p INTERRUPT";
  attribute X_INTERFACE_PARAMETER of irq_f2p : signal is "SENSITIVITY LEVEL_HIGH";
begin
  accel_inst : entity work.shadow_accelerator
    generic map (DIM => DIM, ADDR_WIDTH => ADDR_WIDTH, DATA_WIDTH => DATA_WIDTH)
    port map (
      s_axi_aclk => fclk_clk0, s_axi_aresetn => fclk_reset0_n,
      s_axi_awaddr => s_axi_awaddr, s_axi_awvalid => s_axi_awvalid, s_axi_awready => s_axi_awready,
      s_axi_wdata => s_axi_wdata, s_axi_wstrb => s_axi_wstrb, s_axi_wvalid => s_axi_wvalid, s_axi_wready => s_axi_wready,
      s_axi_bresp => s_axi_bresp, s_axi_bvalid => s_axi_bvalid, s_axi_bready => s_axi_bready,
      s_axi_araddr => s_axi_araddr, s_axi_arvalid => s_axi_arvalid, s_axi_arready => s_axi_arready,
      s_axi_rdata => s_axi_rdata, s_axi_rresp => s_axi_rresp, s_axi_rvalid => s_axi_rvalid,
      s_axi_rready => s_axi_rready, irq => irq_f2p
    );
end architecture;
