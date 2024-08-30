package mqttexporter // import github.com/smnzlnsk/mqttexporter

import (
	"context"
	"fmt"

	mqtt "github.com/eclipse/paho.mqtt.golang"
	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/pdata/pmetric"
)

type mqttExporter struct {
	config *Config
	*marshaler
	client mqtt.Client
	host   component.Host
	cancel context.CancelFunc
}

func newMQTTExporter(cfg *Config) (*mqttExporter, error) {
	uri := fmt.Sprintf("%s:%d", cfg.Broker.Host, cfg.Broker.Port)

	opts := mqtt.NewClientOptions()
	opts.AddBroker(uri)
	opts.SetClientID(cfg.ClientID)

	client := mqtt.NewClient(opts)
	if token := client.Connect(); token.Wait() && token.Error() != nil {
		return nil, token.Error()
	}

	exporter := &mqttExporter{
		config: cfg,
		client: client,
	}
	return exporter, nil
}

func (me *mqttExporter) pushMetrics(ctx context.Context, md pmetric.Metrics) error {
	data, err := me.metricsMarshaler.MarshalMetrics(md)
	if err != nil {
		return err
	}
	// TODO:
	// add host identifier labeling

	// Publish metrics over MQTT
	token := me.client.Publish(me.config.Topic, 0, false, data)
	token.Wait()
	return token.Error()
}

func (me *mqttExporter) start(ctx context.Context, host component.Host) error {
	marshaler, err := newMarshaler(me.config.EncodingExtensionID, host)
	if err != nil {
		return err
	}
	me.marshaler = marshaler
	fmt.Printf("%v", me.marshaler)
	me.host = host
	return nil
}

func (me *mqttExporter) shutdown(ctx context.Context) error {
	if me.cancel != nil {
		me.cancel()
	}
	me.client.Disconnect(250)
	return nil
}
