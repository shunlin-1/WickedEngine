#include "stdafx.h"
#include "VolumeVisWindow.h"

using namespace wi::ecs;
using namespace wi::scene;

void VolumeVisWindow::Create(EditorComponent* _editor)
{
	editor = _editor;
	wi::gui::Window::Create(ICON_VOLUME_VIS " Volume Visualizer",
		wi::gui::Window::WindowControls::COLLAPSE |
		wi::gui::Window::WindowControls::CLOSE |
		wi::gui::Window::WindowControls::FIT_ALL_WIDGETS_VERTICAL);
	SetSize(XMFLOAT2(420, 380));

	closeButton.SetTooltip("Delete Volume Visualizer component");
	OnClose([=](wi::gui::EventArgs args) {
		wi::Archive& archive = editor->AdvanceHistory();
		archive << EditorComponent::HISTORYOP_COMPONENT_DATA;
		editor->RecordEntity(archive, entity);

		editor->GetCurrentScene().volume_visualizers.Remove(entity);

		editor->RecordEntity(archive, entity);
		editor->componentsWnd.RefreshEntityTree();
	});

	auto forEachSelected = [this](auto func) {
		return [this, func](auto args) {
			Scene& scene = editor->GetCurrentScene();
			for (auto& x : editor->translator.selected)
			{
				VolumeVisualizerComponent* vis = scene.volume_visualizers.GetComponent(x.entity);
				if (vis != nullptr) func(vis, args);
			}
		};
	};

	enabledCheckBox.Create("Enabled: ");
	enabledCheckBox.OnClick(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->SetEnabled(args.bValue);
	}));
	AddWidget(&enabledCheckBox);

	rangeMinSlider.Create(-100, 500, 0, 1000, "Range Min: ");
	rangeMinSlider.SetTooltip("Sensor value that maps to the COLD end of the gradient");
	rangeMinSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->valueRangeMin = args.fValue;
	}));
	AddWidget(&rangeMinSlider);

	rangeMaxSlider.Create(-100, 500, 100, 1000, "Range Max: ");
	rangeMaxSlider.SetTooltip("Sensor value that maps to the HOT end of the gradient");
	rangeMaxSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->valueRangeMax = args.fValue;
	}));
	AddWidget(&rangeMaxSlider);

	diffusionSlider.Create(0.01f, 5.0f, 0.5f, 1000, "Diffusion: ");
	diffusionSlider.SetTooltip("How fast the heat blob spreads from each sensor (Gaussian sigma growth rate)");
	diffusionSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->diffusionAlpha = args.fValue;
	}));
	AddWidget(&diffusionSlider);

	sensorReachSlider.Create(0.5f, 50.0f, 5.0f, 1000, "Sensor Reach: ");
	sensorReachSlider.SetTooltip("Maximum radius (world units) each sensor can spread to. Keep around 30% of your box size. Small = localized hot spots, large = sensors bleed into each other.");
	sensorReachSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->sensorReach = args.fValue;
	}));
	AddWidget(&sensorReachSlider);

	edgeSharpnessSlider.Create(0.2f, 10.0f, 1.0f, 1000, "Edge Sharpness: ");
	edgeSharpnessSlider.SetTooltip("How wide is the blend zone between sensors. 1 = soft Gaussian (default), higher = sharper territory boundaries (each sensor holds color until a narrow edge), lower = very smooth smear.");
	edgeSharpnessSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->edgeSharpness = args.fValue;
	}));
	AddWidget(&edgeSharpnessSlider);

	emissivePowerSlider.Create(0.0f, 8.0f, 1.5f, 1000, "Emissive: ");
	emissivePowerSlider.SetTooltip("HDR brightness multiplier. 0 = no light, 1 = normal color, >1 pushes into bloom so the fog glows like it's self-illuminated. 1.5-3.0 gives a nice heat-shimmer look.");
	emissivePowerSlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->emissivePower = args.fValue;
	}));
	AddWidget(&emissivePowerSlider);

	opacitySlider.Create(0.0f, 1.0f, 1.0f, 1000, "Opacity: ");
	opacitySlider.SetTooltip("Final fog visibility multiplier. 1.0 = full, 0.3 = 30% visible (fades the whole effect uniformly while keeping the shape).");
	opacitySlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->opacityScale = args.fValue;
	}));
	AddWidget(&opacitySlider);

	densitySlider.Create(0.0f, 1.0f, 0.2f, 1000, "Density: ");
	densitySlider.SetTooltip("How concentrated the fog is (per-step alpha). Low = broad smooth haze, high = sharp dense hot spots. 0.2 is a good default.");
	densitySlider.OnSlide(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->densityScale = args.fValue;
	}));
	AddWidget(&densitySlider);

	resetButton.Create("Reset Diffusion Time");
	resetButton.SetTooltip("Reset the elapsed time so blobs start from minimum spread");
	resetButton.OnClick(forEachSelected([](VolumeVisualizerComponent* v, wi::gui::EventArgs args) {
		v->elapsedTime = 0.0f;
	}));
	AddWidget(&resetButton);

	infoLabel.Create("");
	infoLabel.SetFitTextEnabled(true);
	AddWidget(&infoLabel);

	SetMinimized(true);
	SetVisible(false);
}

void VolumeVisWindow::SetEntity(Entity _entity)
{
	entity = _entity;
	Scene& scene = editor->GetCurrentScene();
	const VolumeVisualizerComponent* vis = scene.volume_visualizers.GetComponent(entity);
	if (vis == nullptr) return;

	enabledCheckBox.SetCheck(vis->IsEnabled());
	rangeMinSlider.SetValue(vis->valueRangeMin);
	rangeMaxSlider.SetValue(vis->valueRangeMax);
	diffusionSlider.SetValue(vis->diffusionAlpha);
	sensorReachSlider.SetValue(vis->sensorReach);
	edgeSharpnessSlider.SetValue(vis->edgeSharpness);
	emissivePowerSlider.SetValue(vis->emissivePower);
	opacitySlider.SetValue(vis->opacityScale);
	densitySlider.SetValue(vis->densityScale);

	infoLabel.SetText(
		"Place this entity over a region. All IoT sensors in the scene\n"
		"will be visualized as colored blobs inside the box.\n"
		"Total IoT sensors: " + std::to_string(scene.iot_sensors.GetCount())
	);
}

void VolumeVisWindow::ResizeLayout()
{
	wi::gui::Window::ResizeLayout();
	layout.margin_left = 110;
	layout.add(enabledCheckBox);
	layout.add(rangeMinSlider);
	layout.add(rangeMaxSlider);
	layout.add(diffusionSlider);
	layout.add(sensorReachSlider);
	layout.add(edgeSharpnessSlider);
	layout.add(emissivePowerSlider);
	layout.add(opacitySlider);
	layout.add(densitySlider);
	layout.add(resetButton);
	layout.add_fullwidth(infoLabel);
}
