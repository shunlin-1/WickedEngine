#include "stdafx.h"
#include "DissolvePlaneWindow.h"

using namespace wi::ecs;
using namespace wi::scene;

void DissolvePlaneWindow::Create(EditorComponent* _editor)
{
	editor = _editor;
	wi::gui::Window::Create(ICON_DISSOLVE_PLANE " Dissolve Plane",
		wi::gui::Window::WindowControls::COLLAPSE |
		wi::gui::Window::WindowControls::CLOSE |
		wi::gui::Window::WindowControls::FIT_ALL_WIDGETS_VERTICAL);
	SetSize(XMFLOAT2(360, 180));

	closeButton.SetTooltip("Delete Dissolve Plane component");
	OnClose([=](wi::gui::EventArgs args) {
		wi::Archive& archive = editor->AdvanceHistory();
		archive << EditorComponent::HISTORYOP_COMPONENT_DATA;
		editor->RecordEntity(archive, entity);

		editor->GetCurrentScene().dissolve_planes.Remove(entity);

		editor->RecordEntity(archive, entity);
		editor->componentsWnd.RefreshEntityTree();
	});

	auto forEachSelected = [this](auto func) {
		return [this, func](auto args) {
			Scene& scene = editor->GetCurrentScene();
			for (auto& x : editor->translator.selected)
			{
				DissolvePlaneComponent* p = scene.dissolve_planes.GetComponent(x.entity);
				if (p != nullptr) func(p, args);
			}
		};
	};

	enabledCheckBox.Create("Enabled: ");
	enabledCheckBox.SetTooltip("Turns this plane active. Only the first enabled plane in the scene cuts; extras are ignored.");
	enabledCheckBox.OnClick(forEachSelected([](DissolvePlaneComponent* p, wi::gui::EventArgs args) {
		p->SetEnabled(args.bValue);
	}));
	AddWidget(&enabledCheckBox);

	lightPassCheckBox.Create("Light Pass-Through: ");
	lightPassCheckBox.SetTooltip("When ON, dissolve-tagged geometry above the cut plane stops casting shadows —\nlight passes through as if the geometry isn't there. When OFF, faded geometry still shadows normally.");
	lightPassCheckBox.OnClick(forEachSelected([](DissolvePlaneComponent* p, wi::gui::EventArgs args) {
		p->SetLightPassThrough(args.bValue);
	}));
	AddWidget(&lightPassCheckBox);

	edgeWidthSlider.Create(0.01f, 10.0f, 0.5f, 10000, "Edge Width: ");
	edgeWidthSlider.SetTooltip("Width (world units) of the fade band across the cut plane. Larger = softer fade-out.");
	edgeWidthSlider.OnSlide(forEachSelected([](DissolvePlaneComponent* p, wi::gui::EventArgs args) {
		p->edgeWidth = args.fValue;
	}));
	AddWidget(&edgeWidthSlider);

	infoLabel.Create("");
	infoLabel.SetFitTextEnabled(true);
	infoLabel.SetText(
		"Move/rotate this entity to position the cut plane.\n"
		"Local +Y is the plane normal (up = fade side).\n"
		"Only materials with DISSOLVE flag respond."
	);
	AddWidget(&infoLabel);

	SetMinimized(true);
	SetVisible(false);
}

void DissolvePlaneWindow::SetEntity(Entity _entity)
{
	entity = _entity;
	Scene& scene = editor->GetCurrentScene();
	const DissolvePlaneComponent* p = scene.dissolve_planes.GetComponent(entity);
	if (p == nullptr) return;

	enabledCheckBox.SetCheck(p->IsEnabled());
	lightPassCheckBox.SetCheck(p->IsLightPassThrough());
	edgeWidthSlider.SetValue(p->edgeWidth);
}

void DissolvePlaneWindow::ResizeLayout()
{
	wi::gui::Window::ResizeLayout();
	layout.margin_left = 110;
	layout.add(enabledCheckBox);
	layout.add(lightPassCheckBox);
	layout.add(edgeWidthSlider);
	layout.add_fullwidth(infoLabel);
}
