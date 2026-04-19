#pragma once
class EditorComponent;

// Per-entity component window for DissolvePlaneComponent. The entity's
// TransformComponent controls the plane's position and rotation (local +Y is
// the normal), so move/rotate the entity in the scene gizmo to reposition
// the cut plane — no sliders here for XYZ, the standard transform tools work.
class DissolvePlaneWindow : public wi::gui::Window
{
public:
	void Create(EditorComponent* editor);

	EditorComponent* editor = nullptr;
	wi::ecs::Entity entity = wi::ecs::INVALID_ENTITY;
	void SetEntity(wi::ecs::Entity entity);

	wi::gui::CheckBox enabledCheckBox;
	wi::gui::CheckBox lightPassCheckBox;
	wi::gui::Slider   edgeWidthSlider;
	wi::gui::Label    infoLabel;

	void ResizeLayout() override;
};
