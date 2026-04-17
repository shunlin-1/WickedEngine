#pragma once
class EditorComponent;

class VolumeVisWindow : public wi::gui::Window
{
public:
	void Create(EditorComponent* editor);

	EditorComponent* editor = nullptr;
	wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
	void SetEntity(wi::ecs::Entity entity);

	wi::gui::CheckBox enabledCheckBox;
	wi::gui::Slider rangeMinSlider;
	wi::gui::Slider rangeMaxSlider;
	wi::gui::Slider diffusionSlider;
	wi::gui::Slider sensorReachSlider;
	wi::gui::Slider edgeSharpnessSlider;
	wi::gui::Slider emissivePowerSlider;
	wi::gui::Slider opacitySlider;
	wi::gui::Slider densitySlider;
	wi::gui::Button resetButton;
	wi::gui::Label infoLabel;

	void ResizeLayout() override;
};
