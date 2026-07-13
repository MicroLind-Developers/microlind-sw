#include "ui/MainWindow.h"

#include <QApplication>

int main(int argc, char* argv[])
{
    QApplication app(argc, argv);
    QApplication::setApplicationName("MLFS Commander");
    QApplication::setOrganizationName("MicroLind");

    MainWindow window;
    window.show();

    return app.exec();
}
