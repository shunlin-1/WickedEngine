#pragma once
class EditorComponent;

class IoTSensorWindow : public wi::gui::Window
{
public:
	void Create(EditorComponent* editor);

	EditorComponent* editor = nullptr;
	wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
	void SetEntity(wi::ecs::Entity entity);

	wi::gui::CheckBox enabledCheckBox;
	wi::gui::Slider valueSlider;

	void ResizeLayout() override;
};
