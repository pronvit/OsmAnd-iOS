#ifndef OAGpxTrackObjectsProvider_h
#define OAGpxTrackObjectsProvider_h

#include <OsmAndCore/stdlib_common.h>
#include <memory>

#include <OsmAndCore/QtExtensions.h>
#include <QList>
#include <QString>
#include <QVector>

#include <OsmAndCore/CommonTypes.h>
#include <OsmAndCore/Map/IMapObjectsProvider.h>
#include <OsmAndCore/Data/MapObject.h>

class OAGpxTrackObjectsProvider
    : public std::enable_shared_from_this<OAGpxTrackObjectsProvider>
    , public OsmAnd::IMapObjectsProvider
{
    Q_DISABLE_COPY_AND_MOVE(OAGpxTrackObjectsProvider);

public:
    explicit OAGpxTrackObjectsProvider(QList<std::shared_ptr<const OsmAnd::MapObject>> objects);
    virtual ~OAGpxTrackObjectsProvider();

    static std::shared_ptr<const OsmAnd::MapObject> makeObject(
        const QVector<OsmAnd::PointI>& points31,
        const QString& width,
        const QString& colorName);
    static QString colorHexForArgb(int argb);

    virtual OsmAnd::ZoomLevel getMinZoom() const Q_DECL_OVERRIDE;
    virtual OsmAnd::ZoomLevel getMaxZoom() const Q_DECL_OVERRIDE;

    virtual bool supportsNaturalObtainData() const Q_DECL_OVERRIDE;
    virtual bool obtainData(
        const OsmAnd::IMapDataProvider::Request& request,
        std::shared_ptr<OsmAnd::IMapDataProvider::Data>& outData,
        std::shared_ptr<OsmAnd::Metric>* const pOutMetric = nullptr) Q_DECL_OVERRIDE;

    virtual bool supportsNaturalObtainDataAsync() const Q_DECL_OVERRIDE;
    virtual void obtainDataAsync(
        const OsmAnd::IMapDataProvider::Request& request,
        const OsmAnd::IMapDataProvider::ObtainDataAsyncCallback callback,
        const bool collectMetric = false) Q_DECL_OVERRIDE;

private:
    const QList<std::shared_ptr<const OsmAnd::MapObject>> _objects;
};

#endif /* OAGpxTrackObjectsProvider_h */
