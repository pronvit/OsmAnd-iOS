#include "OAGpxTrackObjectsProvider.h"

#include <OsmAndCore/Map/MapDataProviderHelpers.h>
#include <OsmAndCore/Utilities.h>

OAGpxTrackObjectsProvider::OAGpxTrackObjectsProvider(QList<std::shared_ptr<const OsmAnd::MapObject>> objects)
    : _objects(std::move(objects))
{
}

OAGpxTrackObjectsProvider::~OAGpxTrackObjectsProvider()
{
}

std::shared_ptr<const OsmAnd::MapObject> OAGpxTrackObjectsProvider::makeObject(
    const QVector<OsmAnd::PointI>& points31,
    const QString& width,
    const QString& colorName)
{
    auto mapObject = std::make_shared<OsmAnd::MapObject>();
    mapObject->points31 = points31;
    mapObject->isArea = false;
    mapObject->computeBBox31();

    auto attributeMapping = std::make_shared<OsmAnd::MapObject::AttributeMapping>();
    uint32_t idx = 1;
    mapObject->attributeIds.push_back(idx);
    attributeMapping->registerMapping(idx++, QStringLiteral("osmand_gpx"), QStringLiteral("track"));

    const QString widthValue = width.isEmpty() ? QStringLiteral("thin") : width;
    mapObject->additionalAttributeIds.push_back(idx);
    attributeMapping->registerMapping(idx++, QStringLiteral("width"), widthValue);

    const QString colorValue = colorName.isEmpty() ? QStringLiteral("red") : colorName;
    mapObject->additionalAttributeIds.push_back(idx);
    attributeMapping->registerMapping(idx++, QStringLiteral("track_color"), colorValue);

    attributeMapping->verifyRequiredMappingRegistered();
    mapObject->attributeMapping = attributeMapping;
    return mapObject;
}

QString OAGpxTrackObjectsProvider::colorHexForArgb(const int argb)
{
    return QLatin1Char('#') + QString::number(static_cast<uint>(argb), 16).toUpper().rightJustified(8, QLatin1Char('0'));
}

OsmAnd::ZoomLevel OAGpxTrackObjectsProvider::getMinZoom() const
{
    return OsmAnd::ZoomLevel1;
}

OsmAnd::ZoomLevel OAGpxTrackObjectsProvider::getMaxZoom() const
{
    return OsmAnd::MaxZoomLevel;
}

bool OAGpxTrackObjectsProvider::supportsNaturalObtainData() const
{
    return true;
}

bool OAGpxTrackObjectsProvider::obtainData(
    const OsmAnd::IMapDataProvider::Request& request,
    std::shared_ptr<OsmAnd::IMapDataProvider::Data>& outData,
    std::shared_ptr<OsmAnd::Metric>* const pOutMetric)
{
    Q_UNUSED(pOutMetric);

    const auto& tiledRequest = OsmAnd::MapDataProviderHelpers::castRequest<OsmAnd::IMapTiledDataProvider::Request>(request);
    const auto tileBBox = OsmAnd::Utilities::tileBoundingBox31(tiledRequest.tileId, tiledRequest.zoom);

    QList<std::shared_ptr<const OsmAnd::MapObject>> visible;
    for (const auto& object : _objects)
    {
        if (object && object->bbox31.intersects(tileBBox))
            visible.append(object);
    }

    outData = std::make_shared<OsmAnd::IMapObjectsProvider::Data>(
        tiledRequest.tileId,
        tiledRequest.zoom,
        OsmAnd::MapSurfaceType::Undefined,
        visible);
    return true;
}

bool OAGpxTrackObjectsProvider::supportsNaturalObtainDataAsync() const
{
    return false;
}

void OAGpxTrackObjectsProvider::obtainDataAsync(
    const OsmAnd::IMapDataProvider::Request& request,
    const OsmAnd::IMapDataProvider::ObtainDataAsyncCallback callback,
    const bool collectMetric)
{
    OsmAnd::MapDataProviderHelpers::nonNaturalObtainDataAsync(shared_from_this(), request, callback, collectMetric);
}
