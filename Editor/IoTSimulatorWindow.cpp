#include "stdafx.h"
#include "IoTSimulatorWindow.h"

using namespace wi::ecs;
using namespace wi::scene;

void IoTSimulatorWindow::Create(EditorComponent* _editor)
{
	editor = _editor;
	wi::gui::Window::Create(ICON_IOT_SIMULATOR " IoT Simulator",
		wi::gui::Window::WindowControls::COLLAPSE |
		wi::gui::Window::WindowControls::CLOSE |
		wi::gui::Window::WindowControls::FIT_ALL_WIDGETS_VERTICAL);
	SetSize(XMFLOAT2(420, 600));

	closeButton.SetTooltip("Delete IoT Simulator component");
	OnClose([=](wi::gui::EventArgs args) {
		wi::Archive& archive = editor->AdvanceHistory();
		archive << EditorComponent::HISTORYOP_COMPONENT_DATA;
		editor->RecordEntity(archive, entity);

		editor->GetCurrentScene().iot_simulators.Remove(entity);

		editor->RecordEntity(archive, entity);
		editor->componentsWnd.RefreshEntityTree();
	});

	auto forEachSelected = [this](auto func) {
		return [this, func](auto args) {
			Scene& scene = editor->GetCurrentScene();
			for (auto& x : editor->translator.selected)
			{
				IoTSimulatorComponent* sim = scene.iot_simulators.GetComponent(x.entity);
				if (sim != nullptr) func(sim, args);
			}
		};
	};

	enabledCheckBox.Create("Enabled: ");
	enabledCheckBox.SetTooltip("Master switch for this simulator");
	enabledCheckBox.OnClick(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->SetEnabled(args.bValue);
	}));
	AddWidget(&enabledCheckBox);

	driveValueCheckBox.Create("Drive Value: ");
	driveValueCheckBox.SetTooltip("When enabled, simulator writes into IoTSensorComponent::sensorValue each frame");
	driveValueCheckBox.OnClick(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->SetDrivesValue(args.bValue);
	}));
	AddWidget(&driveValueCheckBox);

	driveTransformCheckBox.Create("Drive Transform: ");
	driveTransformCheckBox.SetTooltip("When enabled, simulator writes entity position each frame from the motion pattern");
	driveTransformCheckBox.OnClick(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->SetDrivesTransform(args.bValue);
	}));
	AddWidget(&driveTransformCheckBox);

	// --- Value pattern ---
	valueModeCombo.Create("Value Pattern: ");
	valueModeCombo.AddItem("Sine", (uint64_t)IoTSimulatorComponent::ValueMode::SINE);
	valueModeCombo.AddItem("Random Walk (OU)", (uint64_t)IoTSimulatorComponent::ValueMode::RANDOM_WALK);
	valueModeCombo.AddItem("Ramp + Hold", (uint64_t)IoTSimulatorComponent::ValueMode::RAMP_HOLD);
	valueModeCombo.SetTooltip("Sine: smooth oscillation. Random Walk: mean-reverting noise. Ramp: linear climb to peak.");
	valueModeCombo.OnSelect(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->valueMode = (IoTSimulatorComponent::ValueMode)args.userdata;
	}));
	AddWidget(&valueModeCombo);

	offsetSlider.Create(-100, 500, 50, 1000, "Offset: ");
	offsetSlider.SetTooltip("Center / baseline raw sensor value (e.g. 50°C)");
	offsetSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->offset = args.fValue;
	}));
	AddWidget(&offsetSlider);

	amplitudeSlider.Create(0, 200, 30, 1000, "Amplitude: ");
	amplitudeSlider.SetTooltip("Peak deviation above/below offset");
	amplitudeSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->amplitude = args.fValue;
	}));
	AddWidget(&amplitudeSlider);

	frequencySlider.Create(0.0f, 5.0f, 0.25f, 1000, "Frequency: ");
	frequencySlider.SetTooltip("Hz (sine cycles per second)");
	frequencySlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->frequency = args.fValue;
	}));
	AddWidget(&frequencySlider);

	phaseSlider.Create(0.0f, 6.2832f, 0.0f, 1000, "Phase: ");
	phaseSlider.SetTooltip("Phase offset in radians (use to stagger multiple sensors)");
	phaseSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->phase = args.fValue;
	}));
	AddWidget(&phaseSlider);

	meanReversionSlider.Create(0.0f, 3.0f, 0.3f, 1000, "Reversion: ");
	meanReversionSlider.SetTooltip("Random Walk only: how strongly value snaps back to Offset. Higher = tighter around mean.");
	meanReversionSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->meanReversion = args.fValue;
	}));
	AddWidget(&meanReversionSlider);

	rampDurationSlider.Create(0.1f, 60.0f, 5.0f, 1000, "Ramp Time: ");
	rampDurationSlider.SetTooltip("Ramp+Hold only: seconds to reach Offset+Amplitude");
	rampDurationSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->rampDuration = args.fValue;
	}));
	AddWidget(&rampDurationSlider);

	// --- Motion pattern ---
	motionModeCombo.Create("Motion Pattern: ");
	motionModeCombo.AddItem("Static", (uint64_t)IoTSimulatorComponent::MotionMode::STATIC);
	motionModeCombo.AddItem("Orbit (XZ)", (uint64_t)IoTSimulatorComponent::MotionMode::ORBIT);
	motionModeCombo.AddItem("Ping Pong (X)", (uint64_t)IoTSimulatorComponent::MotionMode::PING_PONG);
	motionModeCombo.OnSelect(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionMode = (IoTSimulatorComponent::MotionMode)args.userdata;
	}));
	AddWidget(&motionModeCombo);

	motionCenterXSlider.Create(-100, 100, 0, 1000, "Center X: ");
	motionCenterXSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionCenter.x = args.fValue;
	}));
	AddWidget(&motionCenterXSlider);

	motionCenterYSlider.Create(-100, 100, 0, 1000, "Center Y: ");
	motionCenterYSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionCenter.y = args.fValue;
	}));
	AddWidget(&motionCenterYSlider);

	motionCenterZSlider.Create(-100, 100, 0, 1000, "Center Z: ");
	motionCenterZSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionCenter.z = args.fValue;
	}));
	AddWidget(&motionCenterZSlider);

	motionRadiusSlider.Create(0.0f, 50.0f, 2.0f, 1000, "Radius: ");
	motionRadiusSlider.SetTooltip("Orbit radius / ping-pong half-length");
	motionRadiusSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionRadius = args.fValue;
	}));
	AddWidget(&motionRadiusSlider);

	motionSpeedSlider.Create(0.0f, 5.0f, 0.5f, 1000, "Motion Speed: ");
	motionSpeedSlider.SetTooltip("Hz (full cycle per second)");
	motionSpeedSlider.OnSlide(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->motionSpeed = args.fValue;
	}));
	AddWidget(&motionSpeedSlider);

	resetButton.Create("Reset Sim Time");
	resetButton.SetTooltip("Reset accumulated simulator time to 0 (restart ramps, reseed random walk)");
	resetButton.OnClick(forEachSelected([](IoTSimulatorComponent* s, wi::gui::EventArgs args) {
		s->_runtime_time = 0.0f;
		s->_runtime_value = s->offset;
		s->_runtime_rng_state = 1;
	}));
	AddWidget(&resetButton);

	infoLabel.Create("");
	infoLabel.SetFitTextEnabled(true);
	AddWidget(&infoLabel);

	SetMinimized(true);
	SetVisible(false);
}

void IoTSimulatorWindow::SetEntity(Entity _entity)
{
	entity = _entity;
	Scene& scene = editor->GetCurrentScene();
	const IoTSimulatorComponent* sim = scene.iot_simulators.GetComponent(entity);
	if (sim == nullptr) return;

	enabledCheckBox.SetCheck(sim->IsEnabled());
	driveValueCheckBox.SetCheck(sim->DrivesValue());
	driveTransformCheckBox.SetCheck(sim->DrivesTransform());

	valueModeCombo.SetSelectedByUserdataWithoutCallback((uint64_t)sim->valueMode);
	offsetSlider.SetValue(sim->offset);
	amplitudeSlider.SetValue(sim->amplitude);
	frequencySlider.SetValue(sim->frequency);
	phaseSlider.SetValue(sim->phase);
	meanReversionSlider.SetValue(sim->meanReversion);
	rampDurationSlider.SetValue(sim->rampDuration);

	motionModeCombo.SetSelectedByUserdataWithoutCallback((uint64_t)sim->motionMode);
	motionCenterXSlider.SetValue(sim->motionCenter.x);
	motionCenterYSlider.SetValue(sim->motionCenter.y);
	motionCenterZSlider.SetValue(sim->motionCenter.z);
	motionRadiusSlider.SetValue(sim->motionRadius);
	motionSpeedSlider.SetValue(sim->motionSpeed);

	const bool hasSensor = scene.iot_sensors.Contains(entity);
	const bool hasTransform = scene.transforms.Contains(entity);
	infoLabel.SetText(
		std::string("Paired IoT Sensor: ") + (hasSensor ? "yes" : "NO — attach one to drive value") + "\n" +
		std::string("Entity Transform:  ") + (hasTransform ? "yes" : "NO — attach one to drive motion")
	);
}

void IoTSimulatorWindow::ResizeLayout()
{
	wi::gui::Window::ResizeLayout();
	layout.margin_left = 130;
	layout.add(enabledCheckBox);
	layout.add(driveValueCheckBox);
	layout.add(driveTransformCheckBox);
	layout.add(valueModeCombo);
	layout.add(offsetSlider);
	layout.add(amplitudeSlider);
	layout.add(frequencySlider);
	layout.add(phaseSlider);
	layout.add(meanReversionSlider);
	layout.add(rampDurationSlider);
	layout.add(motionModeCombo);
	layout.add(motionCenterXSlider);
	layout.add(motionCenterYSlider);
	layout.add(motionCenterZSlider);
	layout.add(motionRadiusSlider);
	layout.add(motionSpeedSlider);
	layout.add(resetButton);
	layout.add_fullwidth(infoLabel);
}
