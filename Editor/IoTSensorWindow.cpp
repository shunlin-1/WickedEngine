#include "stdafx.h"
#include "IoTSensorWindow.h"

using namespace wi::ecs;
using namespace wi::scene;

void IoTSensorWindow::Create(EditorComponent* _editor)
{
	editor = _editor;
	wi::gui::Window::Create(ICON_IOT_SENSOR " IoT Sensor",
		wi::gui::Window::WindowControls::COLLAPSE |
		wi::gui::Window::WindowControls::CLOSE |
		wi::gui::Window::WindowControls::FIT_ALL_WIDGETS_VERTICAL);
	SetSize(XMFLOAT2(380, 120));

	closeButton.SetTooltip("Delete IoT Sensor component");
	OnClose([=](wi::gui::EventArgs args) {
		wi::Archive& archive = editor->AdvanceHistory();
		archive << EditorComponent::HISTORYOP_COMPONENT_DATA;
		editor->RecordEntity(archive, entity);

		editor->GetCurrentScene().iot_sensors.Remove(entity);

		editor->RecordEntity(archive, entity);
		editor->componentsWnd.RefreshEntityTree();
	});

	auto forEachSelected = [this](auto func) {
		return [this, func](auto args) {
			Scene& scene = editor->GetCurrentScene();
			for (auto& x : editor->translator.selected)
			{
				IoTSensorComponent* sensor = scene.iot_sensors.GetComponent(x.entity);
				if (sensor != nullptr) func(sensor, args);
			}
		};
	};

	enabledCheckBox.Create("Enabled: ");
	enabledCheckBox.SetTooltip("Enable or disable this sensor");
	enabledCheckBox.OnClick(forEachSelected([](IoTSensorComponent* s, wi::gui::EventArgs args) {
		s->SetEnabled(args.bValue);
	}));
	AddWidget(&enabledCheckBox);

	valueSlider.Create(1, 100, 50, 1000, "Value: ");
	valueSlider.SetTooltip("Sensor reading. Set externally by IoT feed, Lua, or this slider. Minimum is 1 — value 0 is reserved as an 'empty' sentinel in the density texture.");
	valueSlider.OnSlide(forEachSelected([](IoTSensorComponent* s, wi::gui::EventArgs args) {
		s->sensorValue = args.fValue;
	}));
	AddWidget(&valueSlider);

	SetMinimized(true);
	SetVisible(false);
}

void IoTSensorWindow::SetEntity(Entity _entity)
{
	entity = _entity;
	const IoTSensorComponent* sensor = editor->GetCurrentScene().iot_sensors.GetComponent(entity);
	if (sensor == nullptr) return;

	enabledCheckBox.SetCheck(sensor->IsEnabled());
	valueSlider.SetValue(sensor->sensorValue);
}

void IoTSensorWindow::ResizeLayout()
{
	wi::gui::Window::ResizeLayout();
	layout.margin_left = 100;
	layout.add(enabledCheckBox);
	layout.add(valueSlider);
}
