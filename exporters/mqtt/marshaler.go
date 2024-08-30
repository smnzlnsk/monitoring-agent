package mqttexporter // import github.com/smnzlnsk/mqttexporter

import (
	"fmt"

	"go.opentelemetry.io/collector/component"
	"go.opentelemetry.io/collector/pdata/pmetric"
)

type marshaler struct {
	metricsMarshaler pmetric.Marshaler
}

func newMarshaler(encoding *component.ID, host component.Host) (*marshaler, error) {
	var metricsMarshaler pmetric.Marshaler = &pmetric.ProtoMarshaler{}

	if encoding != nil {
		ext, ok := host.GetExtensions()[*encoding]
		if !ok {
			return nil, fmt.Errorf("unknown encoding %q", encoding)
		}

		metricsMarshaler, _ = ext.(pmetric.Marshaler)
	}

	m := marshaler{
		metricsMarshaler: metricsMarshaler,
	}
	return &m, nil
}
