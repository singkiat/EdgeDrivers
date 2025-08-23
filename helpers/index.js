const fs = require("fs");
const yaml = require("js-yaml");
const pathModule = require("path");

function update_models_lan(path = ".", getdir = () => "") {
  const MODEL_FOLDER = path + "/services/";
  const files = fs.readdirSync(MODEL_FOLDER);
  const services = [];
  files.forEach((file) => {
    let obj = yaml.load(
      fs.readFileSync(MODEL_FOLDER + file, {
        encoding: "utf-8",
      })
    );
    const SPECIFIC_MODEL = getdir(obj) + "/";
    if (!fs.existsSync(path + "/src/services/" + SPECIFIC_MODEL)) {
      fs.mkdirSync(path + "/src/services/" + SPECIFIC_MODEL);
    }
    fs.writeFileSync(
      path + "/src/services/" + SPECIFIC_MODEL + "init.lua",
      "return [[" + JSON.stringify(obj) + "]]"
    );
    services.push(
      ("services/" + SPECIFIC_MODEL).slice(0, -1).replace(/\//g, ".")
    );
  });
  fs.writeFileSync(
    path + "/src/services/init.lua",
    'local json = require "st.json"\n\nreturn {\n' +
      services.map((s) => '  json.decode(require "' + s + '"),').join("\n") +
      "\n}"
  );
}

function update_models_zigbee(path = ".", version) {
  const versionModel = yaml
    .load(fs.readFileSync(path + "/versions.yaml", { encoding: "utf-8" }))
    .find(({ id }) => id === version);
  if (!versionModel) {
    console.log("Version not found ($DRIVER_VERSION=%s)", version);
    return;
  }

  const tmp = path + "/tmp";

  if (fs.existsSync(tmp)) {
    fs.rmSync(tmp, { recursive: true });
  }

  const versionPath = path + (version ? "/versions/" + version : "");

  const profilePrefixes = versionModel.includedProfiles.map((value) => ({
    value,
    regex: new RegExp("^" + value + "-[^-]+-v\\d+$"),
  }));

  fs.cpSync(path + "/capabilities", tmp + "/capabilities", {
    recursive: true,
  });

  fs.cpSync(path + "/src", tmp + "/src", {
    recursive: true,
  });

  fs.cpSync(versionPath, tmp, {
    recursive: true,
  });

  // Copy config.yaml file
  if (fs.existsSync(path + "/config.yaml")) {
    fs.cpSync(path + "/config.yaml", tmp + "/config.yaml");
  }

  fs.cpSync(path + "/profiles", tmp + "/profiles", {
    recursive: true,
    filter: (src) => {
      const name = pathModule.parse(src).name;
      return (
        name === "profiles" ||
        profilePrefixes.some(
          ({ value, regex }) => value === name || regex.test(name)
        )
      );
    },
  });

  let modelsFolder = tmp + "/src/models";
  if (!fs.existsSync(modelsFolder)) {
    fs.mkdirSync(modelsFolder, { recursive: true });
  }
  const fingerprints = yaml.load(
    fs.readFileSync(tmp + "/STATIC-fingerprints.yaml", {
      encoding: "utf-8",
    })
  );
  const directoriesWithModels = [];
  const MODEL_FOLDER = path + "/models/";
  const directories = fs.readdirSync(MODEL_FOLDER);
  directories.forEach((directory) => {
    const SPECIFIC_MODEL = directory + "/";
    const files = fs.readdirSync(MODEL_FOLDER + SPECIFIC_MODEL);
    const manufacturers = [];
    files.forEach((file) => {
      // console.log(file)
      let obj = yaml.load(
        fs.readFileSync(MODEL_FOLDER + SPECIFIC_MODEL + file, {
          encoding: "utf-8",
        })
      );
      if (!obj) {
        return;
      }
      let deviceProfileName = obj.profiles[0].replace(/_/g, "-");
      if (!profilePrefixes.some(({ value, regex }) => value === deviceProfileName || regex.test(deviceProfileName))) {
        return;
      }

      let mfrFolder = tmp + "/src/models/" + SPECIFIC_MODEL;
      if (!fs.existsSync(mfrFolder)) {
        fs.mkdirSync(mfrFolder, { recursive: true });
      }

      directoriesWithModels.push(directory);

      let mfr = file.replace(".yaml", "");
      fs.writeFileSync(
        mfrFolder + mfr + ".lua",
        "return [[" + JSON.stringify(obj) + "]]"
      );
      fingerprints.zigbeeManufacturer.push({
        id: directory + "/" + mfr,
        model: directory,
        manufacturer: mfr,
        deviceProfileName,
        deviceLabel: obj.deviceLabel || "Generic Device",
        zigbeeProfiles: obj.zigbeeProfiles,
        deviceIdentifiers: obj.deviceIdentifiers,
        clusters: obj.clusters,
        datapoints: obj.datapoints || [],
      });
      // console.log(file, JSON.stringify(obj, null, 2));
      manufacturers.push({
        mfr,
        mdl: directory,
        req: "models." + directory + "." + obj.manufacturer,
      });
    });
    if (!manufacturers.length) {
      return;
    }
    fs.writeFileSync(
      tmp + "/src/models/" + SPECIFIC_MODEL + "init.lua",
      'local myutils = require "utils"\n\nreturn {\n  ' +
        manufacturers
          .map(
            ({ mfr, mdl }) =>
              '["' +
              mfr +
              '"] = myutils.load_model_from_json("' +
              mdl +
              '", "' +
              mfr +
              '")'
          )
          .join(",\n  ") +
        "\n}"
    );
  });
  let maxLength = fingerprints.zigbeeManufacturer.reduce(
    (
      acc,
      { model, manufacturer, deviceLabel, deviceProfileName, datapoints = [] }
    ) => {
      const t = [
        model,
        manufacturer.replace(/^_/, "\\_"),
        deviceLabel,
        deviceProfileName,
        datapoints
          .map(({ id }) => ("" + id).padStart(3, " "))
          .filter((v) => v > 0)
          .join(", "),
      ];
      return acc.map((v, i) => Math.max(v, t[i].length));
    },
    [0, 0, 0, 0, 0]
  );

  fs.writeFileSync(
    versionPath + "/DEVICES.md",
    [
      "",
      "Model".padEnd(maxLength[0], " "),
      "Manufacturer".padEnd(maxLength[1], " "),
      "Label".padEnd(maxLength[2], " "),
      "Default profile".padEnd(maxLength[3], " "),
      "Datapoints".padEnd(maxLength[4], " "),
      "",
    ]
      .join(" | ")
      .trim() +
      "\n" +
      [
        "",
        "".padEnd(maxLength[0], "-"),
        "".padEnd(maxLength[1], "-"),
        "".padEnd(maxLength[2], "-"),
        "".padEnd(maxLength[3], "-"),
        "".padEnd(maxLength[4], "-"),
        "",
      ]
        .join(" | ")
        .trim() +
      "\n" +
      fingerprints.zigbeeManufacturer
        .map(
          ({
            model,
            manufacturer,
            deviceLabel,
            deviceProfileName,
            datapoints = [],
          }) =>
            [
              "",
              model.padEnd(maxLength[0], " "),
              manufacturer.replace(/^_/, "\\_").padEnd(maxLength[1], " "),
              deviceLabel.padEnd(maxLength[2], " "),
              deviceProfileName.padEnd(maxLength[3], " "),
              datapoints
                .map(({ id }) => ("" + id).padStart(3, " "))
                .filter((v) => v > 0)
                // .sort((a, b) => -(a < b) || +(a !== b))
                .join(", ")
                .padEnd(maxLength[4], " "),
              "",
            ]
              .join(" | ")
              .trim()
        )
        .join("\n") +
      "\n\n- This is a list of predefined devices, but the driver is NOT limited to those.<br />It should work with any device that expose EF00 cluster.\n"
  );
  fs.writeFileSync(
    tmp + "/src/models/init.lua",
    "return {\n  " +
      directoriesWithModels
        .map((mdl) => '["' + mdl + '"] = require "models.' + mdl + '"')
        .join(",\n  ") +
      "\n}"
  );
  fs.writeFileSync(
    tmp + "/fingerprints.yaml",
    yaml.dump(
      {
        zigbeeManufacturer: fingerprints.zigbeeManufacturer.map(
          ({ datapoints, ...o }) => o
        ),
        zigbeeGeneric: fingerprints.zigbeeGeneric,
        zigbeeThing: fingerprints.zigbeeThing,
      },
      {
        styles: {
          "!!int": "hexadecimal",
        },
      }
    )
  );
}

module.exports = {
  update_models_zigbee,
  update_models_lan,
};
