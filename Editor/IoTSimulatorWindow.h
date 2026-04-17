#pragma once
class EditorComponent;

class IoTSimulatorWindow : public wi::gui::Window
{
public:
	void Create(EditorComponent* editor);

	EditorComponent* editor = nullptr;
	wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
	void SetEntity(wi::ecs::Entity entity);

	wi::gui::CheckBox enabledCheckBox;
	wi::gui::CheckBox driveValueCheckBox;
	wi::gui::CheckBox driveTransformCheckBox;

	wi::gui::ComboBox valueModeCombo;
	wi::gui::Slider offsetSlider;
	wi::gui::Slider amplitudeSlider;
	wi::gui::Slider frequencySlider;
	wi::gui::Slider phaseSlider;
	wi::gui::Slider meanReversionSlider;
	wi::gui::Slider rampDurationSlider;

	wi::gui::ComboBox motionModeCombo;
	wi::gui::Slider motionCenterXSlider;
	wi::gui::Slider motionCenterYSlider;
	wi::gui::Slider motionCenterZSlider;
	wi::gui::Slider motionRadiusSlider;
	wi::gui::Slider motionSpeedSlider;

	wi::gui::Button resetButton;
	wi::gui::Label infoLabel;

	void ResizeLayout() override;
};
