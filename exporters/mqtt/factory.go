package mqttexporter // import github.com/smnzlnsk/mqttexporter

import (
	"context"
	"time"

	"github.com/smnzlnsk/monitoring-agent/exporters/mqtt/internal/metadata"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/exporter"
	"go.opentelemetry.io/collector/exporter/exporterhelper"
)

const (
	defaultInterval   = time.Second * 1
	defaultClientID   = "test-mqtt-exporter-client"
	defaultTopic      = "telemetry/metrics"
	defaultEncoding   = "otlp"
	defaultBroker     = "127.0.0.1"
	defaultBrokerPort = 1883
)

// NewFactory creates a factory for mqtt-exporter
func NewFactory() exporter.Factory {
	return exporter.NewFactory(
		metadata.Type,
		createDefaultConfig,
		exporter.WithMetrics(createMetricsExporter, component.StabilityLevelDevelopment),
	)
}

func createDefaultConfig() component.Config {
	return &Config{
		Interval: string(defaultInterval),
		ClientID: defaultClientID,
		Topic:    defaultTopic,
		Broker: BrokerConfig{
			Host: defaultBroker,
			Port: defaultBrokerPort,
		},
	}
}

func createMetricsExporter(
	ctx context.Context,
	set exporter.Settings,
	cfg component.Config,
) (exporter.Metrics, error) {
	config := (cfg.(*Config))
	me, err := newMQTTExporter(config)
	if err != nil {
		return nil, err
	}

	return exporterhelper.NewMetricsExporter(
		ctx,
		set,
		cfg,
		me.pushMetrics,
		exporterhelper.WithStart(me.start),
		exporterhelper.WithShutdown(me.shutdown),
	)
}