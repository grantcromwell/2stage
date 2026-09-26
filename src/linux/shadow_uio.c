
#include <linux/clk.h>
#include <linux/io.h>
#include <linux/module.h>
#include <linux/of.h>
#include <linux/platform_device.h>
#include <linux/uio_driver.h>

struct shadow_device {
	struct uio_info info;
	void __iomem *regs;
};

static irqreturn_t shadow_interrupt(int irq, struct uio_info *info)
{
	struct shadow_device *shadow = info->priv;
	if (!(readl(shadow->regs + 4) & BIT(2)))
		return IRQ_NONE;
	

	writel(1, shadow->regs);
	readl(shadow->regs);
	return IRQ_HANDLED;
}

static int shadow_irqcontrol(struct uio_info *info, s32 enabled)
{
	struct shadow_device *shadow = info->priv;
	u32 control = readl(shadow->regs);

	if (enabled)
		control |= BIT(2);
	else
		control &= ~BIT(2);
	writel(control, shadow->regs);
	readl(shadow->regs);
	return 0;
}

static int shadow_probe(struct platform_device *pdev)
{
	struct device *dev = &pdev->dev;
	struct shadow_device *shadow;
	struct resource *res;
	struct clk *clk;
	int irq, ret;

	shadow = devm_kzalloc(dev, sizeof(*shadow), GFP_KERNEL);
	if (!shadow)
		return -ENOMEM;
	res = platform_get_resource(pdev, IORESOURCE_MEM, 0);
	if (!res || res->start != 0x43c00000 || resource_size(res) != 0x1000)
		return -EINVAL;
	clk = devm_clk_get_enabled(dev, "aclk");
	if (IS_ERR(clk))
		return dev_err_probe(dev, PTR_ERR(clk), "FCLK0 unavailable\n");
	if (clk_get_rate(clk) != 100000000)
		return dev_err_probe(dev, -EINVAL, "FCLK0 must be 100 MHz\n");
	shadow->regs = devm_ioremap_resource(dev, res);
	if (IS_ERR(shadow->regs))
		return PTR_ERR(shadow->regs);
	if (readl(shadow->regs + 0x5c) != 0x53484431)
		return dev_err_probe(dev, -ENODEV, "SHD1 signature missing\n");
	irq = platform_get_irq(pdev, 0);
	if (irq < 0)
		return irq;
	writel(2, shadow->regs); 
	shadow->info.name = "shadow-accelerator";
	shadow->info.version = "1.0";
	shadow->info.irq = irq;
	shadow->info.handler = shadow_interrupt;
	shadow->info.irqcontrol = shadow_irqcontrol;
	shadow->info.priv = shadow;
	shadow->info.mem[0].name = "registers";
	shadow->info.mem[0].addr = res->start;
	shadow->info.mem[0].size = resource_size(res);
	shadow->info.mem[0].memtype = UIO_MEM_PHYS;
	ret = devm_uio_register_device(dev, &shadow->info);
	if (!ret)
		dev_info(dev, "bound at %pa, Linux IRQ %d, clock %lu Hz\n", &res->start, irq, clk_get_rate(clk));
	return ret;
}
static const struct of_device_id shadow_matches[] = {
	{ .compatible = "statArb,shadow-accelerator-1.0" }, {}
};
MODULE_DEVICE_TABLE(of, shadow_matches);
static struct platform_driver shadow_driver = {
	.probe = shadow_probe,
	.driver = { .name = "shadow-accelerator", .of_match_table = shadow_matches },
};
module_platform_driver(shadow_driver);
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Shadow Q16.16 accelerator UIO and level interrupt driver");
