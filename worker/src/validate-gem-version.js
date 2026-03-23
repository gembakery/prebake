export async function validateGemVersion(gemResponse, parsed) {
  if (!gemResponse.ok) {
    console.error(`Gem ${parsed.name} not found on rubygems.org`);
    return false;
  }

  const versions = await gemResponse.json();

  if (!versions.some((v) => v.number === parsed.version)) {
    console.error(
      `Version ${parsed.version} of ${parsed.name} not found on rubygems.org`,
    );
    return false;
  }

  if (
    versions.some(
      (v) => v.number === parsed.version && v.platform === parsed.platform,
    )
  ) {
    console.log(
      `Skipping build for ${parsed.name}: precompiled gem already available on rubygems.org`,
    );
    return false;
  }

  return true;
}
